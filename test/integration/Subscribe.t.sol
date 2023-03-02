// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {LibDataTypes, TestBase} from "../TestBase.sol";

import {SelfRepayingENS} from "../../src/SelfRepayingENS.sol";

contract SubscribeTests is TestBase {
    /// @dev Test `srens.subscribe()`'s happy path.
    function testFork_subscribe() external {
        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.prank(scoopy, scoopy);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, name, name);
        srens.subscribe(name);

        // Subscribe to the Self Repaying ENS service for `name`.
        vm.prank(scoopy, scoopy);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, "alchemix", "alchemix");
        srens.subscribe("alchemix");

        // `srens.subscribedNames()` should be updated.
        string[] memory names = srens.subscribedNames(scoopy);
        assertEq(names.length, 2, "scoopy should have 2 subscribed names");
        assertEq(names[0], name, "the first name is `name`");
        assertEq(names[1], "alchemix", "the second name is alchemix");
    }

    /// @dev Test `srens.subscribe()` does not revert when subscribing for `name` with another subscriber.
    function testFork_subscribe_whenNameIsUsedBy2Subscribers() external {
        // Act as scoopy, an EOA.
        vm.prank(scoopy, scoopy);
        // Subscribe to the Self Repaying ENS service for `name`.
        srens.subscribe(name);

        // Act as `techno`, an EOA, for the next call.
        address techno = address(0xbabe);
        vm.prank(techno, techno);

        // Subscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Subscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(techno, name, name);
        srens.subscribe(name);

        string[] memory names = srens.subscribedNames(scoopy);
        assertEq(names.length, 1, "scoopy names should not be updated");
        assertEq(names[0], name);

        names = srens.subscribedNames(techno);
        assertEq(names.length, 1, "techno names should be updated");
        assertEq(names[0], name);
    }

    /// @dev Test `srens.getTaskId()`.
    function testFork_getTaskId() external {
        assertEq(srens.getTaskId(scoopy), 0, "there should not be a gelato task for scoopy");
        // Subscribe to the Self Repaying ENS service for `name`.
        vm.prank(scoopy, scoopy);
        srens.subscribe(name);

        LibDataTypes.ModuleData memory moduleData = toolbox.getModuleData(srens, scoopy);
        bytes32 taskId =
            config.gelatoOps.getTaskId(address(srens), address(srens), srens.renew.selector, moduleData, ETH);
        assertEq(srens.getTaskId(scoopy), taskId, "subscribing the first time should create a task");
    }
}

contract SubscribeFailureTests is TestBase {
    /// @dev Test `srens.subscribe()` reverts when inputing a ENS name that doesn't exist.
    function testFork_subscribe_failIfNameDoesNotExist() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that doesn't exist.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.subscribe("dsadsfsdfdsf");
    }

    /// @dev Test `srens.subscribe()` reverts when inputing an expired ENS name that is isn't in its grace period (i.e. available to register).
    function testFork_subscribe_failIfNameIsFullyExpired() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that needs to be re-registered not renewed.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        // This name must be expired and not within its grace period.
        // Found this one randomly ! 😰
        srens.subscribe("sdfsdfsdf");
    }

    /// @dev Test `srens.subscribe()` reverts when subscribing for the same name twice with the same subscriber.
    function testFork_subscribe_failIfSubscribeTwiceForTheSameName() external {
        // Act as scoopy, an EOA.
        vm.startPrank(scoopy, scoopy);
        // Subscribe to the Self Repaying ENS service for `name`.
        srens.subscribe(name);
        // Try to subscribe a second time as `scoopy`.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.subscribe(name);
    }
}
