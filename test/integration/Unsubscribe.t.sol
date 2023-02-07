// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "../TestBase.sol";

import {SelfRepayingENS} from "../../src/SelfRepayingENS.sol";

contract UnsubscribeTests is TestBase {
    function setUp() public override {
        // Call base setUp();
        super.setUp();

        // `scoopy` subscribe for `name`.
        vm.prank(scoopy, scoopy);
        srens.subscribe(name);
    }

    function testFork_SetUp() external {
        // Assert the snapshotted state.
        string[] memory names = srens.subscribedNames(scoopy);
        assertEq(names.length, 1, "scoopy should have a name to renew");
    }

    /// @dev Test `srens.unsubscribe()`'s happy path.
    function testFork_unsubscribe() external {
        vm.prank(scoopy, scoopy);
        // Unsubscribe to the Self Repaying ENS service for `name`.
        // `srens` should emit a {Unubscribed} event.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Unsubscribe(scoopy, name, name);
        srens.unsubscribe(name);

        string[] memory names = srens.subscribedNames(scoopy);
        assertEq(names.length, 0, "it should have remove the name from the scoopy to renew list");
    }
}

contract UnsubscribeFailureTests is TestBase {
    /// @dev Test `srens.unsubscribe()` reverts when `subscriber` did not subscribe to renew `name`.
    function testFork_unsubscribe_failIfSubscriberDidNotSubscribe() external {
        // Act as scoopy, an EOA, for the next call.
        vm.prank(scoopy, scoopy);

        // Try to subscribe with a ENS name that doesn't exist.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        srens.unsubscribe("dsadsfsdfdsf");
    }
}
