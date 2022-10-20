// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IAlchemistV2 } from "alchemix/interfaces/IAlchemistV2.sol";
import { AlchemicTokenV2 } from "alchemix/AlchemicTokenV2.sol";
import { ETHRegistrarController, BaseRegistrarImplementation } from "ens/ethregistrar/ETHRegistrarController.sol";
import { toDaysWadUnsafe, wadExp, wadDiv } from "solmate/utils/SignedWadMath.sol";

import { ICurveAlETHPool } from "./interfaces/ICurveAlETHPool.sol";
import { ICurveCalc } from "./interfaces/ICurveCalc.sol";
import { IGelatoOps } from "./interfaces/IGelatoOps.sol";

/// @title SelfRepayingENS
/// @author Wary
contract SelfRepayingENS {

    /// @notice The ENS name renewal duration in seconds.
    uint256 constant public renewalDuration = 365 days;

    /// @notice The Alchemix alETH alchemistV2 contract.
    IAlchemistV2 immutable alchemist;

    /// @notice The Alchemix alETH AlchemicTokenV2 contract.
    AlchemicTokenV2 immutable alETH;

    /// @notice The alETH + ETH Curve Pool contract.
    ICurveAlETHPool immutable alETHPool;

    /// @notice The CurveCalc contract.
    ICurveCalc immutable curveCalc;

    /// @notice The ENS ETHRegistrarController (i.e. .eth controller) contract.
    ETHRegistrarController immutable controller;

    /// @notice The ENS BaseRegistrarImplementation (i.e. .eth registrar) contract.
    BaseRegistrarImplementation immutable registrar;

    /// @notice The Gelato contract.
    address payable public immutable gelato;

    /// @notice The Gelato Ops contract.
    IGelatoOps immutable gelatoOps;

    /// @notice The Gelato address for ETH.
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice An event which is emitted when a user subscribe for an self repaying ENS name renewals.
    ///
    /// @param subscriber The address of the user subscribed to this service.
    /// @param indexedName The ENS name to renew.
    /// @param name The ENS name to renew.
    /// @dev We also expose the non indexed name for consumers (e.g. UI).
    event Subscribed(address indexed subscriber, string indexed indexedName, string name);

    /// @notice An event which is emitted when a user unsubscribe to the self repaying ENS name renewal service.
    ///
    /// @param subscriber The address of the user unsubscribed from this service.
    /// @param indexedName The ENS name to renew.
    /// @param name The ENS name to not renew anymore.
    /// @dev We also expose the non indexed name for consumers.
    event Unsubscribed(address indexed subscriber, string indexed indexedName, string name);

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
        IAlchemistV2 _alchemist,
        ICurveAlETHPool _alETHPool,
        ICurveCalc _curveCalc,
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        IGelatoOps _gelatoOps
    ) payable {
        alchemist = _alchemist;
        alETHPool = _alETHPool;
        curveCalc = _curveCalc;
        controller = _controller;
        registrar = _registrar;
        gelatoOps = _gelatoOps;

        alETH = AlchemicTokenV2(alchemist.debtToken());
        gelato = _gelatoOps.gelato();

        // Approve the `alETHPool` Curve Pool to transfer an (almost) unlimited amount of `alETH` tokens.
        alETH.approve(address(_alETHPool), type(uint256).max);
    }

    /// @notice Subscribe to the self repaying ENS renewals service for `name`.
    ///
    /// @dev It creates a Gelato task to monitor `name`'s expiry. Fees are paid on task execution.
    ///
    /// @notice `name` must exist or this call will revert an {IllegalArgument} error.
    ///
    /// @notice Emits a {Subscribed} event.
    ///
    /// @notice **_NOTE:_** The `SelfRepayingENS` contract must have enough `AlchemistV2.mintAllowance()` to renew `name`. The can be done via the `AlchemistV2.approveMint()` method.
    /// @notice **_NOTE:_** The `msg.sender` must make sure they have enough `AlchemistV2.totalValue()` to cover `name` renewal fee.
    ///
    /// @param name The ENS name to monitor and renew.
    /// @return task The Gelato task id.
    /// @dev We return the generated task id to simplify the `this.getTaskId()` Solidity test.
    function subscribe(string memory name) external returns (bytes32 task) {
        // Check `name` exists and is within its grace period if expired.
        // The ENS grace period is 90 days but we chose to have a 1 day margin.
        if (registrar.nameExpires(uint256(keccak256(bytes(name)))) + 89 days < block.timestamp) {
            // The name needs to be registered not renewed.
            revert IllegalArgument();
        }

        // Create a gelato task to monitor `name`'s expiry and renew it.
        // We choose to pay Gelato when executing the task.
        task = gelatoOps.createTaskNoPrepayment(
            address(this),
            this.renew.selector,
            address(this),
            abi.encodeCall(this.checker, (name, msg.sender)),
            ETH
        );

        emit Subscribed(msg.sender, name, name);
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

        emit Unsubscribed(msg.sender, name, name);
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
    function checker(string memory name, address subscriber) external view returns (bool canExec, bytes memory execPayload) {
        unchecked {
            // Check `name` expiry.
            // Try to limit the renew transaction base fee which means limiting the gelato fee.
            uint256 expiresAt = registrar.nameExpires(uint256(keccak256(bytes(name))));
            if (block.basefee > _getVariableMaxBaseFee(int256(block.timestamp) - int256(expiresAt))) {
                // Log the reason.
                return (false, bytes("Base fee too high"));
            }

            // Return the Gelato task payload to execute. It must call `this.renew(name, subscriber)`.
            return (true, abi.encodeCall(
                this.renew,
                (name, subscriber)
            ));
        }
    }

    /// @notice Renew `name` by minting new debt from `subscriber`'s Alchemix account.
    ///
    /// @notice **_NOTE:_** This function can only be called by a Gelato Executor.
    ///
    /// @notice **_NOTE:_** When renewing, the `SelfRepayingENS` contract must have **mintAllowance()** to mint new alETH debt tokens on behalf of **subscriber** to cover **name** renewal and the Gelato fee costs. This can be done via the `AlchemistV2.approveMint()` method.
    ///
    /// @dev We annotate it payable to make it cheaper. Do not send ETH.
    ///
    /// @param name The ENS name to renew.
    /// @param subscriber The address of the subscriber.
    function renew(string calldata name, address subscriber) external payable {
        unchecked {
            // Only the Gelato Ops contract can call this function.
            if (msg.sender != address(gelatoOps)) {
                revert Unauthorized();
            }

            // Get `name` rent price.
            uint256 namePrice = controller.rentPrice(name, renewalDuration);
            // Get the gelato fee in ETH.
            (uint256 gelatoFee, ) = gelatoOps.getFeeDetails();
            // The amount of ETH needed to pay the ENS renewal using Gelato.
            uint256 neededETH = namePrice + gelatoFee;

            // ⚠️ Curve alETH-ETH pool, the biggest alETH pool, makes it difficult and expensive to get an EXACT ETH amount back so we must use `curveCalc.get_dx()` outside of a transaction.
            // Get the EXACT amount of debt (i.e. alETH) to mint from the Curve Pool by asking the CurveCalc contract.
            uint256 alETHToMint = _getAlETHToMint(neededETH);

            // Mint `alETHToMint` of alETH (i.e. debt token) from `subscriber`'s Alchemix account.
            alchemist.mintFrom(subscriber, alETHToMint, address(this));
            // Execute a Curve Pool exchange for `alETHToMint` amount of alETH tokens to at least `needETH` ETH.
            alETHPool.exchange(
                1, // alETH
                0, // ETH
                alETHToMint,
                neededETH
            );

            // Renew `name` for its expiry data + `renewalDuration` first.
            controller.renew{value: namePrice}(name, renewalDuration);

            // Pay the Gelato executor with all the ETH left. No ETH will be stuck in this contract.
            (bool success, ) = gelato.call{value: address(this).balance}("");
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
        // The Gelato Ops getTaskId function is deprecated so we need to compute it ourselves.
        // https://github.com/gelatodigital/ops/blob/66095337ef1d2f107e68a3c2c91d7302ceccb33a/contracts/Ops.sol#L329
        bytes32 resolverHash = keccak256(abi.encode(
            address(this),
            abi.encodeCall(this.checker, (name, subscriber))
        ));
        // https://github.com/gelatodigital/ops/blob/66095337ef1d2f107e68a3c2c91d7302ceccb33a/contracts/Ops.sol#L348
        return keccak256(abi.encode(
            address(this),
            address(this),
            this.renew.selector,
            false,
            ETH,
            resolverHash
        ));
    }

    /// @dev Get the current alETH amount to get `neededETH` ETH amount back in from a Curve Pool exchange.
    ///
    /// @param neededETH The ETH amount to get back from the Curve alETH exchange.
    /// @return The exact alETH amount to swap to get `neededETH` ETH back form a Curve exchange.
    function _getAlETHToMint(uint256 neededETH) internal view returns (uint256) {
        unchecked {
            uint256[2] memory b = alETHPool.get_balances();
            return curveCalc.get_dx(
                2,
                [b[0], b[1], 0, 0, 0, 0, 0, 0],
                alETHPool.A(),
                alETHPool.fee(),
                [uint256(1e18), 1e18, 0, 0, 0, 0, 0, 0],
                [uint256(1), 1, 0, 0, 0, 0, 0, 0],
                false,
                1, // alETH
                0, // ETH
                neededETH + 1 // Because of Curve rounding errors
            );
        }
    }

    /// @dev Get the variable maximum base fee for this expired name.
    ///
    /// @param name The ENS name to renew.
    /// @return The maximum base fee in wei allowed to renew `name`.
    function getVariableMaxBaseFee(string calldata name) external view returns (uint256) {
        unchecked {
            uint256 expiryDate = registrar.nameExpires(uint256(keccak256(bytes(name))));
            return _getVariableMaxBaseFee(int256(block.timestamp) - int256(expiryDate));
        }
    }

    /// @dev Get the variable maximum base fee allowed to renew a name depending on its expiry time.
    ///
    /// @dev The formula is: y = x + e^(x / 2.62 - 30); where y is the base fee limit in gwei and x is the number of days before (expiry time - 90 days).
    ///
    /// @param expiredDuration The expired time in seconds of an ENS name.
    /// @dev expiredDuration can be negative since we want to try to renew BEFORE the ENS name is expired.
    /// @return The maximum base fee allowed in wei.
    function _getVariableMaxBaseFee(int256 expiredDuration) internal pure returns (uint256) {
        unchecked {
            if (expiredDuration < -90 days) {
                // We don't want to try to renew before.
                return 0;
            } else if (expiredDuration > 0) {
                // Remove the base fee limit after expiry.
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
            uint256 maxBaseFeeWad = x + a;
            // In gwei;
            return maxBaseFeeWad / 1e9;
        }
    }

    /// @notice To receive ETH payments.
    ///
    /// @dev To receive ETH from alETHPool.exchange().
    /// @dev All other received ETH will be sent to the next Gelato executor.
    receive() external payable {}
}
