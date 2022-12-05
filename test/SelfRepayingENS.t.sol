// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, stdError} from "../lib/forge-std/src/Test.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";
import {AlchemicTokenV2} from "../lib/alchemix/src/AlchemicTokenV2.sol";
import {WETHGateway} from "../lib/alchemix/src/WETHGateway.sol";
import {Whitelist} from "../lib/alchemix/src/utils/Whitelist.sol";

import {SelfRepayingENSStub, SelfRepayingENS, LibDataTypes} from "./stubs/SelfRepayingENS.sol";
import {DeploySRENS} from "../script/DeploySRENS.s.sol";
import {ToolboxLocal, Toolbox} from "../script/ToolboxLocal.s.sol";

contract SelfRepayingENSTest is Test {
    using FixedPointMathLib for uint256;

    /* --- TEST CONFIG --- */
    ToolboxLocal toolbox;
    Toolbox.Config config;
    SelfRepayingENS srens;
    address scoopy = address(0xbadbabe);
    string name = "SelfRepayingENS";
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 constant gelatoFee = 0.001 ether;

    /// @dev Copied from the `SelfRepayingENS` contract.
    event Subscribed(address indexed subscriber, string indexed indexedName, string name);
    event Unsubscribed(address indexed subscriber, string indexed indexedName, string name);
    /// @dev ENS `ETHRegistrarController` contract event
    event NameRenewed(string name, bytes32 indexed label, uint256 cost, uint256 expires);

    /// @dev Setup the environment for the tests.
    function setUp() external {
        // Make sure we run the tests on a mainnet fork.
        string memory RPC_MAINNET = vm.envString("RPC_MAINNET");
        uint256 BLOCK_NUMBER_MAINNET = vm.envUint("BLOCK_NUMBER_MAINNET");
        vm.createSelectFork(RPC_MAINNET, BLOCK_NUMBER_MAINNET);
        require(block.chainid == 1, "Tests should be run on a mainnet fork");

        toolbox = new ToolboxLocal();
        // Deploy the AlETHRouter contract first.
        toolbox.deployTestRouter();
        // Deploy the SelfRepayingENS contract.
        srens = toolbox.deployTestSRENS();
        // Get the mainnet config.
        config = toolbox.getConfig();

        // The contract is ready to be used.
        (bool isReady, string memory message) = toolbox.check(srens);
        assertTrue(isReady);
        assertEq(message, "Contract ready !");

        // Give 100 ETH to Scoopy Trooples even if he doesn't need it 🙂.
        vm.label(scoopy, "scoopy");
        vm.deal(scoopy, 100 ether);

        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get the first supported yield ETH token.
        address[] memory supportedTokens = config.alchemist.getSupportedYieldTokens();
        // Create an Alchemix account.
        config.wethGateway.depositUnderlying{value: 10 ether}(
            address(config.alchemist), supportedTokens[0], 10 ether, scoopy, 1
        );

        // Check `name`'s rent price.
        uint256 registrationDuration = config.controller.MIN_REGISTRATION_DURATION();
        uint256 namePrice = config.controller.rentPrice(name, registrationDuration);

        // Register `name`.
        // To register a ENS name we must first send a commitment, wait some time then register it.
        // Get the commitment.
        bytes32 secret = keccak256(bytes("SuperSecret"));
        bytes32 commitment = config.controller.makeCommitment(name, scoopy, secret);
        // Submit the commitment to the `ETHRegistrarController`.
        config.controller.commit(commitment);
        // Wait the waiting period.
        vm.warp(block.timestamp + config.controller.minCommitmentAge());
        // Register `name` for `namePrice` and `registrationDuration`.
        // ENS recommend sending at least a 5% premium to cover the price fluctuations. They send the leftover ETH back.
        uint256 namePriceWithPremium = namePrice * 105 / 100;
        config.controller.register{value: namePriceWithPremium}(name, scoopy, registrationDuration, secret);

        vm.stopPrank();
    }

    /// @dev Test the happy path of the entire Alchemix + AlETHRouter + SelfRepayingENS + ENS + Gelato integration.
    ///
    /// @dev **_NOTE:_** It is pretty difficult to perfectly test complex protocols locally when they rely on bots as they usually don't give integrators test mocks.
    /// @dev **_NOTE:_** In the following tests we won't care about Alchemix/Yearn bots and we manually simulate Gelato's.
    function testFullIntegration() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);
        // Scoopy, the subscriber, needs to allow `router` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(config.router), type(uint256).max);
        // Scoopy, the subscriber, needs to allow `srens` to use the `router`.
        config.router.approve(address(srens), type(uint256).max);

        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribed(scoopy, name, name);
        srens.subscribe(name);

        vm.stopPrank();

        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 90 days);

        // `srens` checker function should return false if base fee is too high to renew.
        {
            (bool canExec1, bytes memory execPayload1) = srens.checker(name, scoopy);
            assertFalse(canExec1);
            assertEq(execPayload1, bytes("Base fee too high"));
        }

        // Wait for `name` to be in its renew period.
        vm.warp(expiresAt - 10 days);
        // Set the base fee below the max base fee allowed to renew.
        vm.fee(80 gwei);

        // `srens` checker function should tell Gelato to execute the task by return true and the its payload.
        (bool canExec, bytes memory execPayload) = srens.checker(name, scoopy);
        assertTrue(canExec);
        assertEq(execPayload, abi.encodeCall(srens.renew, (name, scoopy)));

        (int256 previousDebt,) = config.alchemist.accounts(scoopy);
        uint256 namePrice = config.controller.rentPrice(name, srens.renewalDuration());

        // Gelato now execute the defined task.
        // `srens` called by Gelato should renew `name` for `renewalDuration` for `namePrice` by minting some alETH debt.
        vm.expectEmit(true, true, true, true, address(config.controller));
        emit NameRenewed(name, labelHash, namePrice, expiresAt + srens.renewalDuration());
        execRenewTask(gelatoFee, name, scoopy);

        // Check `name`'s renewal increased `scoopy`'s Alchemix debt.
        (int256 newDebt,) = config.alchemist.accounts(scoopy);
        assertTrue(newDebt >= previousDebt + int256(namePrice + gelatoFee));
    }

    /// @dev Test `srens.subscribe()`'s happy path.
    function testSubscribe() public {
        // Act as scoopy, an EOA.
        vm.prank(scoopy, scoopy);

        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribed(scoopy, name, name);
        bytes32 task = srens.subscribe(name);

        // `srens.getTaskId()` should return the same task id.
        assertEq(srens.getTaskId(scoopy, name), task);
    }

    /// @dev Test `srens.subscribe()` reverts when inputing a ENS name that doesn't exist.
    function testSubscribeWhenNameDoesNotExist() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that doesn't exist.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.subscribe("dsadsfsdfdsf");
    }

    /// @dev Test `srens.subscribe()` reverts when inputing an expired ENS name that is isn't in its grace period (i.e. available to register).
    function testSubscribeWhenNameIsFullyExpired() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that needs to be re-registered not renewed.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        // This name must be expired and not within its grace period.
        // Found this one randomly ! 😰
        srens.subscribe("sdfsdfsdf");
    }

    /// @dev Test `srens.subscribe()` reverts when subscribing twice with the same subscriber.
    function testSubscribeTwiceWithTheSameSubscriber() external {
        // Subscribe once as `scoopy` for `name`.
        testSubscribe();

        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe a second time as `scoopy`.
        vm.expectRevert("Ops.createTask: Duplicate task"); // from GelatoOps.
        srens.subscribe(name);
    }

    /// @dev Test `srens.subscribe()` reverts when subscribing `name` with another subscriber.
    function testSubscribeTwiceWithAnotherSubscriber() external {
        // Subscribe once as `scoopy` for `name`.
        testSubscribe();

        // Act as another, an EOA, for the next call.
        vm.prank(address(0x1), address(0x1));

        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribed(address(0x1), name, name);
        srens.subscribe(name);
    }

    /// @dev Test `srens.unsubscribe()`'s happy path.
    function testUnsubscribe() external {
        // Subscribe once as `scoopy` for `name`.
        testSubscribe();

        vm.prank(scoopy, scoopy);

        // Unsubscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Unubscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Unsubscribed(scoopy, name, name);
        srens.unsubscribe(name);
    }

    /// @dev Test `srens.unsubscribe()` reverts when `subscriber` did not subscribe to renew `name`.
    function testUnsubscribeWhenSubscriberDidNotSubscribe() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that doesn't exist.
        vm.expectRevert("Ops.cancelTask: Task not found"); // from Gelato Ops.
        srens.unsubscribe("dsadsfsdfdsf");
    }

    /// @dev Test `srens.checker()`'s happy path.
    function testChecker() external {
        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 4 days);

        // Set the base fee below the max base fee allowed to renew.
        vm.fee(101 gwei);

        // Wait for `name` to be in its grace period.
        // `srens` checker function should tell Gelato to execute the task by return true and the its payload.
        (bool canExec, bytes memory execPayload) = srens.checker(name, scoopy);
        assertTrue(canExec);
        assertEq(execPayload, abi.encodeCall(srens.renew, (name, scoopy)));
    }

    /// @dev Test `srens.checker()`'s returns false when the base fee is too high.
    function testCheckerWhenBaseFeeTooHigh() external {
        // Wait for `name` to be in its grace period.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 80 days);

        // Set the base fee.
        vm.fee(30 gwei);

        // `srens` checker function should return false as `name` is not expired.
        (bool canExec, bytes memory execPayload) = srens.checker(name, scoopy);
        assertFalse(canExec);
        assertEq(execPayload, bytes("Base fee too high"));
    }

    /// @dev Test the internal function `srens._getVariableMaxBaseFee()` returns the correct base fee limit.
    function testVariableMaxRenewBaseFee() external {
        SelfRepayingENSStub stub = new SelfRepayingENSStub(
            config.router,
            config.controller,
            config.registrar,
            config.gelatoOps
        );
        // We don't want to try to renew before 90 days before expiry.
        assertEq(stub.publicGetVariableMaxBaseFee(-90 days), 0);
        // 80 days before expiry we want to renew at a max base fee of 10 gwei.
        assertEq(stub.publicGetVariableMaxBaseFee(-80 days), 10 gwei);
        // 40 days before expiry we want to renew at a max base fee of 50 gwei.
        assertApproxEqAbs(stub.publicGetVariableMaxBaseFee(-40 days), 50 gwei, 1 gwei);
        // 10 days before expiry we want to renew at a max base fee of around 80 gwei.
        assertApproxEqAbs(stub.publicGetVariableMaxBaseFee(-10 days), 80 gwei, 2 gwei);
        // 2 days before expiry we want to renew at a max base fee of around 125 gwei.
        assertApproxEqAbs(stub.publicGetVariableMaxBaseFee(-2 days), 125 gwei, 1 gwei);
        // Since expiry we remove the base fee limit.
        assertEq(stub.publicGetVariableMaxBaseFee(1), type(uint256).max);
    }

    /// @dev Test `srens.getVariableMaxBaseFee()` returns the correct base fee limit for `name`.
    function testGetVariableMaxBaseFeeByName() external {
        // Warp to 90 days before expiry.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 90 days);

        // Before being expired, it should return 0.
        assertEq(srens.getVariableMaxBaseFee(name), 0);

        // Wait for `name` to be in its 90 days renew period.
        vm.warp(expiresAt - 40 days);

        // 40 days before expiry we want to renew at a max base fee of 50 gwei.
        assertApproxEqAbs(srens.getVariableMaxBaseFee(name), 50 gwei, 1 gwei);
    }

    /// @dev Test `srens.renew()` reverts when the caller isn't the `GelatoOps` contract.
    function testRenewWhenUnauthorized() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to renew `name` without being the GelatoOps contract.
        vm.expectRevert(SelfRepayingENS.Unauthorized.selector);
        srens.renew(name, scoopy);
    }

    /// @dev Test `srens.renew()` reverts when the user didn't give `srens` enough mint allowance.
    function testRenewWhenNotEnoughMintAllowance() external {
        // Act as a Gelato Ops
        vm.prank(address(config.gelatoOps));

        // Try to renew `name` without approving `srens` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srens.renew(name, scoopy);

        // Act as Scoopy, an EOA.
        vm.prank(scoopy, scoopy);

        // Allow `router` to mint debt but not enough to renew `name`.
        config.alchemist.approveMint(address(config.router), 1);
        // Scoopy, the subscriber, needs to allow `srens` to use the `router`.
        config.router.approve(address(srens), 1);

        // Act as a Gelato Ops
        vm.prank(address(config.gelatoOps));

        // Try to renew `name` without approving `srens` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srens.renew(name, scoopy);
    }

    /// @dev Test `srens.renew()` reverts when the user don't have enough available debt to cover the `name` renewal.
    function testRenewWhenNotEnoughAvailableDebt() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get `scoopy`'s total collateral value.
        // TODO: Solve the Solidity versioning problem when using the `AlchemistV2` contract ABI instead of the `IAlchemistV2` interface to avoid this low level call.
        (, bytes memory b) = address(config.alchemist).call(abi.encodeWithSignature("totalValue(address)", (scoopy)));
        uint256 totalValue = abi.decode(b, (uint256));
        // Mint all of `scoopy`'s possible debt.
        config.alchemist.mint(totalValue.divWadDown(config.alchemist.minimumCollateralization()), scoopy);

        // Scoopy, the subscriber, needs to allow `router` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(config.router), type(uint256).max);
        // Scoopy, the subscriber, needs to allow `srens` to use the `router`.
        config.router.approve(address(srens), type(uint256).max);

        vm.stopPrank();

        // Act as a Gelato Operator for the next call.
        vm.prank(address(config.gelatoOps));

        // Try to renew `name` without enough collateral to cover the renew cost.
        vm.expectRevert(abi.encodeWithSignature("Undercollateralized()"));
        srens.renew(name, scoopy);
    }

    /// @dev Test `Multicall.multicall()` feature happy path.
    function testMulticall() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Prepare multicall data.
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(srens.subscribe, (name));
        data[1] = abi.encodeCall(srens.subscribe, ("alchemix"));
        data[2] = abi.encodeCall(srens.unsubscribe, (name));
        // Subscribe to the `srens` service for multiple names and unsubscribe for one.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribed(scoopy, name, name);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribed(scoopy, "alchemix", name);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Unsubscribed(scoopy, name, name);
        srens.multicall(data);
    }

    /// @dev Test `Multicall.multicall()` feature reverts the entire transaction on revert.
    function testMulticallWhenNameDoesNotExist() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Prepare multicall data.
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(srens.subscribe, ("dsadsfsdfdsf"));
        data[1] = abi.encodeCall(srens.subscribe, ("alchemix"));
        // Try to subscribe to the `srens` service for multiple names with one that doesn't exist.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.multicall(data);
    }

    /// @dev Simulate a Gelato Ops call with fees.
    function execRenewTask(uint256 fee, string memory _name, address subscriber) internal {
        LibDataTypes.ModuleData memory moduleData = toolbox.getResolveData(srens, _name, subscriber);

        // Act as the Gelato main contract.
        vm.prank(config.gelato);

        // Execute the renew Gelato Task for `fee`.
        config.gelatoOps.exec(
            address(srens),
            address(srens),
            abi.encodeCall(srens.renew, (_name, subscriber)),
            moduleData,
            fee,
            ETH,
            false,
            true
        );
    }
}
