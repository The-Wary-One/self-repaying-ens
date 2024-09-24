// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IGelato} from "../../lib/gelato/contracts/integrations/Types.sol";

import {TestBase} from "../TestBase.sol";

contract RenewalScenarioTests is TestBase {
    /// @dev Test the happy path of the entire Alchemix + SelfRepayingENS + ENS + Gelato interaction.
    ///
    /// @dev **_NOTE:_** It is pretty difficult to perfectly test complex protocols locally when they rely on bots as they usually don't give integrators test mocks.
    /// @dev **_NOTE:_** In the following tests we won't care about Alchemix/Yearn bots and we manually simulate Gelato's.
    function testFork_renewalScenario_happyPath() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);

        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);

        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, name, name);
        srens.subscribe(name);

        vm.stopPrank();

        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 90 days);

        {
            (bool canExec1, bytes memory execPayload1) = srens.checker(scoopy);
            assertFalse(canExec1, "checker should return false when gas price is too high to renew");
            assertEq(execPayload1, bytes("no names to renew"), "check the log message");
        }

        // Wait for `name` to be in its renew period.
        vm.warp(expiresAt - 10 days);

        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertTrue(canExec, "checker should tell Gelato to execute the task");
        assertEq(execPayload, abi.encodeCall(srens.renew, (name, scoopy)), "check the task payload");

        (int256 previousDebt,) = config.alchemist.accounts(scoopy);
        uint256 namePrice = config.controller.rentPrice(name, 365 days);
        IGelato gelato = IGelato(config.gelatoAutomate.gelato());
        uint256 previousGelatoBalance = gelato.feeCollector().balance;

        // Gelato now execute the defined task.
        // `srens` called by Gelato should renew `name` for `renewalDuration` for `namePrice` by minting some alETH debt.
        vm.expectEmit(true, true, true, true, address(config.controller));
        emit NameRenewed(name, labelHash, namePrice, expiresAt + 365 days);
        execRenewTask(gelatoFee, name, scoopy);

        (int256 newDebt,) = config.alchemist.accounts(scoopy);
        assertTrue(newDebt >= previousDebt + int256(namePrice + gelatoFee), "name renewal should increase scoopy debt");

        uint256 newGelatoBalance = gelato.feeCollector().balance;
        assertTrue(newGelatoBalance == previousGelatoBalance + gelatoFee, "Gelato should have been paid");
    }

    function testFork_renewalScenario_whenNameIsInItsGracePeriod() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);
        // Scoopy, the subscriber, needs to allow `srens` to mint enough alETH debt token to pay for the renewal.
        config.alchemist.approveMint(address(srens), type(uint256).max);
        // Subscribe to the Self Repaying ENS service for `name`.
        srens.subscribe(name);

        vm.stopPrank();

        // Warp to some time after `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt + 1 days);

        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertTrue(canExec, "should tell gelato to renew name");
        assertEq(execPayload, abi.encodeCall(srens.renew, (name, scoopy)), "check the task payload");

        (int256 previousDebt,) = config.alchemist.accounts(scoopy);
        uint256 namePrice = config.controller.rentPrice(name, 365 days);

        // Gelato now execute the defined task.
        // `srens` called by Gelato should renew `name` for `renewalDuration` for `namePrice` by minting some alETH debt.
        vm.expectEmit(true, true, true, true, address(config.controller));
        emit NameRenewed(name, labelHash, namePrice, expiresAt + 365 days);
        execRenewTask(gelatoFee, name, scoopy);

        (int256 newDebt,) = config.alchemist.accounts(scoopy);
        assertTrue(newDebt >= previousDebt + int256(namePrice + gelatoFee), "the renewal should increase scoopy debt");
    }
}
