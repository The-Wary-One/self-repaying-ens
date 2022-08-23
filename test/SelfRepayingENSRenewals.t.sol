// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Test, console2, stdError } from "forge-std/Test.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { WETHGateway } from "alchemix/WETHGateway.sol";
import { Whitelist } from "alchemix/utils/Whitelist.sol";
import {
    SelfRepayingENSRenewals,
    IAlchemistV2,
    ETHRegistrarController,
    BaseRegistrarImplementation,
    IAlETHCurvePool,
    IOps,
    Events
} from "src/SelfRepayingENSRenewals.sol";

contract SelfRepayingENSRenewalsTest is Test {

    using FixedPointMathLib for uint256;

    /* --- MAINNET CONFIG --- */
    WETHGateway constant wethGateway = WETHGateway(payable(0xA22a7ec2d82A471B1DAcC4B37345Cf428E76D67A));
    IAlchemistV2 constant alchemist = IAlchemistV2(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c); // AlETH alchemist
    IAlETHCurvePool constant alETHPool = IAlETHCurvePool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e);
    ETHRegistrarController constant controller = ETHRegistrarController(0x283Af0B28c62C092C9727F1Ee09c02CA627EB7F5);
    BaseRegistrarImplementation constant registrar = BaseRegistrarImplementation(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    address constant gelatoOps = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

    /* --- TEST CONFIG --- */
    SelfRepayingENSRenewals srer;
    address scoopy = address(0xbadbabe);
    string name = "SelfRepayingENSRenewals";

    /// @dev Setup the environment for the tests.
    function setUp() external {
        // Make sure we run the tests on a mainnet fork.
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 MAINNET_BLOCK_NUMBER = vm.envUint("MAINNET_BLOCK_NUMBER");
        vm.createSelectFork(MAINNET_RPC_URL, MAINNET_BLOCK_NUMBER);
        require(block.chainid == 1, "Tests should be run on a mainnet fork");

        // Deploy the SelfRepayingENSRenewals contract.
        srer = new SelfRepayingENSRenewals(
            alchemist,
            wethGateway,
            alETHPool,
            controller,
            registrar,
            gelatoOps
        );

        // Give 100 ETH to Scoopy Trooples even if doesn't need it 🙂.
        vm.label(scoopy, "scoopy");
        vm.deal(scoopy, 100e18);

        // Add the `srer` contract address to WETHGateway's whitelist.
        {
            Whitelist whitelist = Whitelist(wethGateway.whitelist());
            vm.prank(whitelist.owner());
            whitelist.add(address(srer));
            assertTrue(whitelist.isWhitelisted(address(srer)));
        }
        // Add the `srer` contract address to alETH AlchemistV2's whitelist.
        {
            Whitelist whitelist = Whitelist(alchemist.whitelist());
            vm.prank(whitelist.owner());
            whitelist.add(address(srer));
            assertTrue(whitelist.isWhitelisted(address(srer)));
        }

        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get the first supported yield ETH token.
        address[] memory supportedTokens = alchemist.getSupportedYieldTokens();
        // Create an Alchemix account.
        wethGateway.depositUnderlying{value: 10e18}(
            address(alchemist),
            supportedTokens[0],
            10e18,
            scoopy,
            1
        );

        // Check `name`'s rent price.
        uint256 registrationDuration = controller.MIN_REGISTRATION_DURATION();
        uint256 rentPrice = controller.rentPrice(name, registrationDuration);

        // Register `name`.
        // To register a ENS name we must first send a commitment, wait some time then register it.
        // Get the commitment.
        bytes32 secret = keccak256(bytes("SuperSecret"));
        bytes32 commitment = controller.makeCommitment(
            name,
            scoopy,
            secret
        );
        // Submit the commitment to the `ETHRegistrarController`.
        controller.commit(commitment);
        // Wait the waiting period.
        vm.warp(block.timestamp + controller.minCommitmentAge());
        // Register `name` for `rentPrice` and `registrationDuration`.
        // ENS recommend sending at least a 5% premium to cover the price fluctuations. They send the leftover ETH back.
        uint256 rentPriceWithPremium = rentPrice * 105 / 100;
        controller.register{value: rentPriceWithPremium}(
            name,
            scoopy,
            registrationDuration,
            secret
        );

        vm.stopPrank();
    }

    /// @dev ENS `ETHRegistrarController` contract event
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);

    /// @dev Test the happy path of the entire Alchemix + SelfRepayingENSRenewals + ENS + Gelato integration.
    ///
    /// @dev **_NOTE:_** It is pretty difficult to perfectly test complex protocols locally when they rely on bots as they usually don't give integrators test mocks.
    /// @dev **_NOTE:_** In the following tests i won't care about Alchemix/Yearn bots and i manually simulate Gelato's.
    function testFullIntegration() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);
        // Scoopy, the subscriber, needs to allow `srer` to mint enough alETH debt token to pay for the renewal.
        alchemist.approveMint(address(srer), type(uint256).max);

        // Subscribe to the Self Repaying ENS Renewals service for `name`.
        // `srer` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srer));
        emit Events.Subscribed(scoopy, name);
        srer.subscribe(name);

        vm.stopPrank();

        // Act as a Gelato Operator.
        vm.startPrank(gelatoOps);

        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expires = registrar.nameExpires(uint256(labelHash));
        vm.warp(expires - 1 days);

        // `srer` checker function should return false as `name` is not expired.
        {
            (bool canExec, ) = srer.checker(name, scoopy);
            assertFalse(canExec);
        }

        // Wait for `name` to be in its grace period.
        vm.warp(expires + 1 days);

        // `srer` checker function should tell Gelato to execute the task by return true and the its payload.
        {
            (bool canExec, bytes memory execPayload) = srer.checker(name, scoopy);
            assertTrue(canExec);
            assertEq(execPayload, abi.encodeCall(srer.renew, (name, scoopy)));
        }

        (int256 previousDebt, ) = alchemist.accounts(scoopy);

        // Gelato now execute the defined task.
        // `srer` called by Gelato should renew `name` for `renewalDuration` for `rentPrice` by minting some alETH debt.
        uint256 renewalDuration = srer.renewalDuration();
        uint256 rentPrice = controller.rentPrice(name, renewalDuration);
        vm.expectEmit(true, true, true, true, address(controller));
        emit NameRenewed(name, labelHash, rentPrice, expires + renewalDuration);
        srer.renew(name, scoopy);

        vm.stopPrank();

        // Check `name`'s renewal increased `scoopy`'s Alchemix debt.
        (int256 newDebt, ) = alchemist.accounts(scoopy);
        (uint256 gelatoFee, ) = IOps(gelatoOps).getFeeDetails();
        assertTrue(newDebt >= previousDebt + int256(rentPrice + gelatoFee));
    }

    /// @dev Test `srer.subscribe()` reverts when inputing a ENS name that doesn't exist.
    function testSubscribeWhenNameDoesNotExist() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that doesn't exists.
        vm.expectRevert(SelfRepayingENSRenewals.IllegalArgument.selector);
        srer.subscribe("dsadsfsdfdsf");
    }

    /// @dev Test `srer.renew()` reverts when the user didn't give `srer` enough mint allowance.
    function testRenewWhenNotEnoughMintAllowance() external {
        // Act as a Gelato Operator for the next call.
        vm.prank(gelatoOps);

        // Try to renew `name` without approving `srer` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srer.renew(name, scoopy);

        // Act as Scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);

        // Allow `srer` to mint debt but not enough to renew `name`.
        uint256 renewalDuration = srer.renewalDuration();
        uint256 rentPrice = controller.rentPrice(name, renewalDuration);
        alchemist.approveMint(address(srer), rentPrice - 1);

        vm.stopPrank();

        // Act as a Gelato Operator for the next call.
        vm.prank(gelatoOps);

        // Try to renew `name` without approving `srer` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srer.renew(name, scoopy);
    }

    /// @dev Test `srer.renew()` reverts when the user don't have enough collateral to cover the `name` renewal.
    function testRenewWhenNotEnoughCollateral() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get `scoopy`'s total collateral value.
        // TODO: Solve the Solidity versioning problem when using the `AlchemistV2` contract ABI instead of the `IAlchemistV2` interface to avoid this low level call.
        (, bytes memory b) = address(alchemist).call(abi.encodeWithSignature("totalValue(address)", (scoopy)));
        uint256 totalValue = abi.decode(b, (uint256));
        // Mint all of `scoopy`'s possible debt.
        alchemist.mint(totalValue.divWadDown(alchemist.minimumCollateralization()), scoopy);

        // Allow `srer` to mint debt.
        alchemist.approveMint(address(srer), type(uint256).max);

        vm.stopPrank();

        // Act as a Gelato Operator for the next call.
        vm.prank(gelatoOps);

        // Try to renew `name` without enough collateral to cover the renew cost.
        vm.expectRevert(abi.encodeWithSignature("Undercollateralized()"));
        srer.renew(name, scoopy);
    }
}
