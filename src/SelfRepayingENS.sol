// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {toDaysWadUnsafe, wadExp, wadDiv} from "../lib/solmate/src/utils/SignedWadMath.sol";
import {AlETHRouter} from "../lib/aleth-router/src/AlETHRouter.sol";
import {
    ETHRegistrarController,
    BaseRegistrarImplementation
} from "../lib/ens-contracts/contracts/ethregistrar/ETHRegistrarController.sol";
import {Ops, LibDataTypes} from "../lib/ops/contracts/Ops.sol";
import {ProxyModule} from "../lib/ops/contracts/taskModules/ProxyModule.sol";
import {IOpsProxyFactory} from "../lib/ops/contracts/interfaces/IOpsProxyFactory.sol";
import {Multicall} from "../lib/openzeppelin/contracts/utils/Multicall.sol";

/// @title SelfRepayingENS
/// @author Wary
contract SelfRepayingENS is Multicall {
    /// @notice The ENS name renewal duration in seconds.
    uint256 constant renewalDuration = 365 days;

    /// @notice The Alchemix alETH router contract.
    AlETHRouter immutable router;

    /// @notice The ENS ETHRegistrarController (i.e. .eth controller) contract.
    ETHRegistrarController immutable controller;

    /// @notice The ENS BaseRegistrarImplementation (i.e. .eth registrar) contract.
    BaseRegistrarImplementation immutable registrar;

    /// @notice The Gelato contract.
    address payable immutable gelato;

    /// @notice The Gelato Ops contract.
    Ops immutable gelatoOps;

    /// @notice The dedicated Gelato proxy executing the renew tasks.
    address public immutable dedicatedExecutorProxy;

    /// @notice The Gelato address for ETH.
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice An event which is emitted when a user subscribe for an self repaying ENS name renewals.
    ///
    /// @param subscriber The address of the user subscribed to this service.
    /// @param indexedName The ENS name to renew.
    /// @param name The ENS name to renew.
    /// @dev We also expose the non indexed name for consumers (e.g. UI).
    event Subscribe(address indexed subscriber, string indexed indexedName, string name);

    /// @notice An event which is emitted when a user unsubscribe to the self repaying ENS name renewal service.
    ///
    /// @param subscriber The address of the user unsubscribed from this service.
    /// @param indexedName The ENS name to renew.
    /// @param name The ENS name to not renew anymore.
    /// @dev We also expose the non i
    /// ndexed name for consumers.
    event Unsubscribe(address indexed subscriber, string indexed indexedName, string name);

    /// @notice An error used to indicate that an action could not be completed because of an illegal argument was passed to the function.
    error IllegalArgument();

    /// @notice An error used to indicate that a caller is not authorized to perform an action.
    error Unauthorized();

    /// @notice An error used to indicate that a transfer failed.
    error FailedTransfer();

    /// @notice Initialize the contract.
    ///
    /// @dev We annotate it payable to make it cheaper. Do not send ETH.
    constructor(
        AlETHRouter _router,
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        Ops _gelatoOps
    ) payable {
        router = _router;
        controller = _controller;
        registrar = _registrar;
        gelatoOps = _gelatoOps;

        gelato = _gelatoOps.gelato();
        address proxyModule = gelatoOps.taskModuleAddresses(LibDataTypes.Module.PROXY);
        dedicatedExecutorProxy = ProxyModule(proxyModule).opsProxyFactory().determineProxyAddress(address(this));
    }

    /// @notice Subscribe to the self repaying ENS renewals service for `name`.
    ///
    /// @dev It creates a Gelato task to monitor `name`'s expiry. Fees are paid on task execution.
    ///
    /// @notice `name` must exist or this call will revert an {IllegalArgument} error.
    /// @notice Emits a {Subscribed} event.
    ///
    /// @notice **_NOTE:_** The `SelfRepayingENS` contract must have enough `AlETHRouter.allowance()` to renew `name`. The can be done via the `AlETHRouter.approve()` method.
    /// @notice **_NOTE:_** The `msg.sender` must make sure they have enough `AlchemistV2.totalValue()` to cover `name` renewal fee.
    ///
    /// @param name The ENS name to monitor and renew.
    /// @return task The Gelato task id.
    /// @dev We return the generated task id to simplify the `this.getTaskId()` Solidity test.
    function subscribe(string memory name) external returns (bytes32 task) {
        // Check `name` exists and is within its grace period if expired.
        // The ENS grace period is 90 days.
        if (registrar.nameExpires(uint256(keccak256(bytes(name)))) + 90 days < block.timestamp) {
            // The name needs to be registered not renewed.
            revert IllegalArgument();
        }

        // Create a gelato task to monitor `name`'s expiry and renew it.
        // We choose to pay Gelato when executing the task.
        task =
            gelatoOps.createTask(address(this), abi.encode(this.renew.selector), _getModuleData(msg.sender, name), ETH);

        emit Subscribe(msg.sender, name, name);
    }

    /// @notice Unsubscribe to the self repaying ENS renewals service for `name`.
    ///
    /// @notice Emits a {Unsubscribed} event.
    ///
    /// @notice **_NOTE:_** The `subscriber` (i.e. caller) can only unsubscribe from one of their renewals.
    ///
    /// @param name The ENS name to not monitor anymore.
    function unsubscribe(string memory name) external {
        // Get the Gelato task id.
        // This way is cheaper than using a mapping from subscriber`s address to taskId but returns a random value if the caller did not subscribe for `name`.
        // The taskId is checked by Gelato in the `cancelTask` below.
        bytes32 taskId = getTaskId(msg.sender, name);

        // Cancel the Gelato task if it exists or reverts.
        gelatoOps.cancelTask(taskId);

        emit Unsubscribe(msg.sender, name, name);
    }

    /// @notice Check if `name` should be renewed.
    ///
    /// @dev This is a Gelato resolver function. It is called by their network to know when and how to execute the renew task.
    ///
    /// @param name The ENS name whose expiry is checked.
    /// @param subscriber The address of the subscriber.
    ///
    /// @return canExec The bool is true when `name` is expired.
    /// @dev It tells Gelato when to execute the task (i.e. when it is true).
    /// @return execPayload The abi encoded call to execute.
    /// @dev It tells Gelato how to execute the task. We use this view function to prepare all the possible data for free and make the renewal cheaper.
    function checker(string memory name, address subscriber)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        unchecked {
            // Check `name` expiry.
            // Try to limit the renew transaction gas price which means limiting the gelato fee.
            uint256 expiresAt = registrar.nameExpires(uint256(keccak256(bytes(name))));
            if (tx.gasprice > _getVariableMaxGasPrice(int256(block.timestamp) - int256(expiresAt))) {
                // Log the reason.
                return (false, bytes("gas price too high"));
            }

            // Return the Gelato task payload to execute. It must call `this.renew(name, subscriber)`.
            return (true, abi.encodeCall(this.renew, (name, subscriber)));
        }
    }

    /// @notice Renew `name` by minting new debt from `subscriber`'s Alchemix account.
    ///
    /// @notice **_NOTE:_** This function can only be called by a Gelato Executor.
    /// @notice **_NOTE:_** When renewing, the `AlETHRouter` and the `SelfRepayingENS` contracts must have **allowance()** to mint new alETH debt tokens on behalf of **subscriber** to cover **name** renewal and the Gelato fee costs. This can be done via the `AlchemistV2.approveMint()` and `AlETHRouter.approve()` methods.
    ///
    /// @dev We annotate it payable to make it cheaper. Do not send ETH.
    ///
    /// @param name The ENS name to renew.
    /// @param subscriber The address of the subscriber.
    function renew(string calldata name, address subscriber) external payable {
        unchecked {
            // Only the dedicated Gelato Ops Proxy contract can call this function.
            // Without it any Gelato task created from other contract could call `renew` for `name` using `subscriber`'s Alchemix account.
            if (msg.sender != dedicatedExecutorProxy) {
                revert Unauthorized();
            }

            // Get `name` rent price.
            uint256 namePrice = controller.rentPrice(name, renewalDuration);
            // Get the gelato fee in ETH.
            (uint256 gelatoFee,) = gelatoOps.getFeeDetails();
            // The amount of ETH needed to pay the ENS renewal using Gelato.
            uint256 neededETH = namePrice + gelatoFee;

            // Borrow `neededETH` amount of ETH from `subscriber` Alchemix account.
            router.borrowAndSendETHFrom(subscriber, address(this), neededETH);

            // Renew `name` for its expiry data + `renewalDuration` first.
            controller.renew{value: namePrice}(name, renewalDuration);

            // Pay the Gelato executor with all the ETH left. No ETH will be stuck in this contract.
            (bool success,) = gelato.call{value: address(this).balance}("");
            if (!success) revert FailedTransfer();
        }
    }

    /// @notice Get the Self Repaying ENS task id created by `subscriber` to renew `name`.
    ///
    /// @dev This is a helper function to get a Gelato task id.
    ///
    /// @notice **_NOTE:_** This function returns a "random" value if the task does not exists. Make sure you call it with a subscribed `subscriber` for `name`.
    ///
    /// @param subscriber The address of the task creator (i.e. subscriber).
    /// @param name The name to monitor and renew.
    /// @return The task id.
    /// @dev This is a Gelato task id.
    ///
    /// @param name The ENS name to renew.
    /// @param subscriber The address of the subscriber.
    function getTaskId(address subscriber, string memory name) public view returns (bytes32) {
        LibDataTypes.ModuleData memory moduleData = _getModuleData(subscriber, name);
        return gelatoOps.getTaskId(address(this), address(this), this.renew.selector, moduleData, ETH);
    }

    /// @dev Helper function to get the Gelato module data.
    function _getModuleData(address subscriber, string memory name)
        internal
        view
        returns (LibDataTypes.ModuleData memory moduleData)
    {
        moduleData = LibDataTypes.ModuleData({modules: new LibDataTypes.Module[](2), args: new bytes[](2)});

        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;
        moduleData.modules[1] = LibDataTypes.Module.PROXY;

        moduleData.args[0] = abi.encode(address(this), abi.encodeCall(this.checker, (name, subscriber)));
        moduleData.args[1] = bytes("");
    }

    /// @dev Get the variable maximum gas price for this expired name.
    ///
    /// @param name The ENS name to renew.
    /// @return The maximum gas price in wei allowed to renew `name`.
    function getVariableMaxGasPrice(string calldata name) external view returns (uint256) {
        unchecked {
            uint256 expiryDate = registrar.nameExpires(uint256(keccak256(bytes(name))));
            return _getVariableMaxGasPrice(int256(block.timestamp) - int256(expiryDate));
        }
    }

    /// @dev Get the variable maximum gas price allowed to renew a name depending on its expiry time.
    ///
    /// @dev The formula is: y = x + e^(x / 2.62 - 30); where y is the gas price limit in gwei and x is the number of days before (expiry time - 90 days).
    ///
    /// @param expiredDuration The expired time in seconds of an ENS name.
    /// @dev expiredDuration can be negative since we want to try to renew BEFORE the ENS name is expired.
    /// @return The maximum gas price allowed in wei.
    function _getVariableMaxGasPrice(int256 expiredDuration) internal pure returns (uint256) {
        unchecked {
            if (expiredDuration < -90 days) {
                // We don't want to try to renew before.
                return 0;
            } else if (expiredDuration > 0) {
                // Remove the gas price limit after expiry.
                return type(uint256).max;
            }
            // Between 90 and 0 days before expiry.
            // x = (expiredDuration + 90) / 1 days; in wad.
            uint256 x = uint256(toDaysWadUnsafe(uint256(expiredDuration + int256(90 days)))); // Safe here.
            // exp = x / 2.62 - 30; can be negative, in wad.
            int256 exponant = wadDiv(int256(x), 2.62e18) - 30e18;
            // a = e^exp; in wad.
            uint256 a = uint256(wadExp(exponant));
            // y = x + a; in wad.
            uint256 maxGasPriceWad = x + a;
            // In gwei;
            return maxGasPriceWad / 1e9;
        }
    }

    /// @notice To receive ETH payments.
    ///
    /// @dev To receive ETH from AlETHRouter.borrowAndSendETH().
    /// @dev All other received ETH will be sent to the next Gelato executor.
    receive() external payable {}
}
