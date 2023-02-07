// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "../TestBase.sol";

import {SelfRepayingENS} from "../../src/SelfRepayingENS.sol";

contract MulticallTests is TestBase {
    /// @dev Test `Multicall.multicall()` feature happy path.
    function testFork_multicall() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Prepare multicall data.
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(srens.subscribe, (name));
        data[1] = abi.encodeCall(srens.subscribe, ("alchemix"));
        data[2] = abi.encodeCall(srens.unsubscribe, (name));
        // Subscribe to the `srens` service for multiple names and unsubscribe for one.
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, name, name);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Subscribe(scoopy, "alchemix", name);
        vm.expectEmit(true, true, false, false, address(srens));
        emit Unsubscribe(scoopy, name, name);
        srens.multicall(data);

        string[] memory names = srens.subscribedNames(scoopy);
        assertEq(names.length, 1, "scoopy should have 1 name to renew");
        assertEq(names[0], "alchemix", "scoopy should have the alchemix name to renew");
    }
}

contract MulticallFailureTests is TestBase {
    /// @dev Test `Multicall.multicall()` feature reverts the entire transaction on revert.
    function testFork_multicall_failIfNameDoesNotExist() external {
        // Act as Scoopy, an EOA. Alchemix checks msg.sender === tx.origin to know if sender is an EOA.
        vm.startPrank(scoopy, scoopy);

        // Prepare multicall data.
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(srens.subscribe, ("dsadsfsdfdsf"));
        data[1] = abi.encodeCall(srens.subscribe, ("alchemix"));
        // Try to subscribe to the `srens` service for multiple names with one that doesn't exist.
        vm.expectRevert(SelfRepayingENS.IllegalArgument.selector);
        // Subscribe to the `srens` service for multiple names.
        srens.multicall(data);
    }
}
