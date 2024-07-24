// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {stdError} from "../../lib/forge-std/src/Test.sol";

import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

import {TestBase} from "../TestBase.sol";

import {SelfRepayingENS} from "../../src/SelfRepayingENS.sol";

contract RenewTests is TestBase {
    bytes32 labelHash;
    uint256 expiresAt;
    int256 previousDebt;
    uint256 namePrice;
    uint256 previousGelatoBalance;

    function setUp() public override {
        // Call base setUp();
        super.setUp();

        vm.startPrank(scoopy, scoopy);
        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);
        // Subscribe as `scoopy` for `name`.
        srens.subscribe(name);

        labelHash = keccak256(bytes(name));
        expiresAt = config.registrar.nameExpires(uint256(labelHash));

        (previousDebt,) = config.alchemist.accounts(scoopy);
        namePrice = config.controller.rentPrice(name, 365 days);
        previousGelatoBalance = config.gelatoAutomate.gelato().balance;
        // Wait for `name` to be in its renew period.
        vm.warp(expiresAt - 10 days);
        vm.stopPrank();
    }

    /// @dev Test `srens.renew()` happy path.
    function testFork_renew() external {
        // techno now execute the defined task.
        vm.prank(address(0xbabe));
        // `srens` called by Gelato should renew `name` for `renewalDuration` for `namePrice` by minting some alETH debt.
        vm.expectEmit(true, true, true, true, address(config.controller));
        emit NameRenewed(name, labelHash, namePrice, expiresAt + 365 days);
        srens.renew(name, scoopy);

        (int256 newDebt,) = config.alchemist.accounts(scoopy);
        assertTrue(newDebt >= previousDebt + int256(namePrice), "name renewal should increase scoopy debt");
    }

    /// @dev Test `srens.renew()` pays Gelato.
    function testFork_renew_whenCalledByGelatoOps() external {
        // Gelato now execute the defined task.
        // `srens` called by Gelato should renew `name` for `renewalDuration` for `namePrice` by minting some alETH debt.
        vm.expectEmit(true, true, true, true, address(config.controller));
        emit NameRenewed(name, labelHash, namePrice, expiresAt + 365 days);
        execRenewTask(gelatoFee, name, scoopy);

        (int256 newDebt,) = config.alchemist.accounts(scoopy);
        assertTrue(newDebt >= previousDebt + int256(namePrice + gelatoFee), "name renewal should increase scoopy debt");

        uint256 newGelatoBalance = config.gelatoAutomate.gelato().balance;
        assertTrue(newGelatoBalance == previousGelatoBalance + gelatoFee, "Gelato should have been paid");
    }
}

contract RenewFailureTests is TestBase {
    using FixedPointMathLib for uint256;

    /// @dev Test `srens.renew()` reverts when a `subscriber` did not subcribe to renew `name` and it is not time to renew it.
    function testFork_renew_failIfIllegalArgument() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to renew `name` without being one to renew for `subscriber`.
        // We do not trust the `Gelato` Executors.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.renew("badname", scoopy);

        // Act as GelatoOps.
        vm.prank(address(config.gelatoAutomate));

        // Try to renew `name` when its not time to renew it.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.renew(name, scoopy);
    }

    /// @dev Test `srens.renew()` reverts when the user didn't give `srens` enough mint allowance.
    function testFork_renew_failIfNotEnoughMintAllowance() external {
        // Subscribe as `scoopy` for `name`.
        vm.prank(scoopy, scoopy);
        srens.subscribe(name);

        // Act as a the GelatoOps.
        vm.prank(address(config.gelatoAutomate));

        // Try to renew `name` without approving `srens` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srens.renew(name, scoopy);

        // Act as Scoopy, an EOA.
        vm.prank(scoopy, scoopy);

        // Allow `srens` to mint debt but not enough to renew `name`.
        config.alchemist.approveMint(address(srens), 1);

        // Act as a the GelatoOps.
        vm.prank(address(config.gelatoAutomate));

        // Try to renew `name` without approving `srens` to mint debt.
        vm.expectRevert(stdError.arithmeticError);
        srens.renew(name, scoopy);
    }

    /// @dev Test `srens.renew()` reverts when the user don't have enough available debt to cover the `name` renewal.
    function testFork_renew_failIfNotEnoughAvailableDebt() external {
        // Subscribe as `scoopy` for `name`.
        vm.prank(scoopy, scoopy);
        srens.subscribe(name);

        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Get `scoopy`'s total collateral value.
        // TODO: Solve the Solidity versioning problem when using the `AlchemistV2` contract ABI instead of the `IAlchemistV2` interface to avoid this low level call.
        (, bytes memory b) = address(config.alchemist).call(abi.encodeWithSignature("totalValue(address)", (scoopy)));
        uint256 totalValue = abi.decode(b, (uint256));
        // Mint all of `scoopy`'s possible debt.
        config.alchemist.mint(totalValue.divWadDown(config.alchemist.minimumCollateralization()), scoopy);

        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);

        vm.stopPrank();

        // Act as a the GelatoOps.
        vm.prank(address(config.gelatoAutomate));

        // Try to renew `name` without enough collateral to cover the renew cost.
        vm.expectRevert(abi.encodeWithSignature("Undercollateralized()"));
        srens.renew(name, scoopy);
    }
}
