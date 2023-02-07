// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {stdJson} from "../../lib/forge-std/src/Test.sol";

import {TestBase} from "../TestBase.sol";

contract CheckerTests is TestBase {
    /// @dev Test `srens.checker()`'s happy path.
    function testFork_checker() external {
        // Subscribe as `scoopy` for `name` and "alchemix".
        vm.startPrank(scoopy, scoopy);
        // The order is important to this test.
        srens.subscribe("alchemix"); // Expiry in 2026.09.21 at 13:24 (UTC+02:00).
        srens.subscribe(name);
        vm.stopPrank();

        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 4 days);

        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertTrue(canExec, "checker should tell Gelato to renew `name` since it's the closest to its expiry");
        assertEq(
            execPayload,
            abi.encodeCall(srens.renew, (name, scoopy)),
            "checker should tell Gelato to renew name since it's the closest to its expiry"
        );
    }

    /// @dev Test `srens.checker()` with a high number of names.
    function testFork_checker_withHighNamesNumber() external {
        // Subscribe as `scoopy` for `name`.
        vm.startPrank(scoopy, scoopy);
        srens.subscribe(name);

        // Prepare multicall data.
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/integration/data/names.json");
        string memory json = vm.readFile(path);
        string[] memory names = stdJson.readStringArray(json, ".data");
        bytes[] memory data = new bytes[](100);
        for (uint256 i; i < 100; i++) {
            data[i] = abi.encodeCall(srens.subscribe, (names[i]));
        }
        // Subscribe to the `srens` service for multiple names.
        srens.multicall(data);
        vm.stopPrank();

        // Warp to some time before `name` expiry date.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 4 days);

        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertTrue(canExec, "checker should tell Gelato to renew `name` since it's the closest to its expiry");
        assertEq(
            execPayload,
            abi.encodeCall(srens.renew, (name, scoopy)),
            "checker should tell Gelato to renew name since it's the closest to its expiry"
        );
    }
}

contract CheckerFailureTests is TestBase {
    /// @dev Test `srens.checker()`'s returns false when there is no name to renew.
    function testFork_checker_failIfNoNameToRenew() external {
        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertFalse(canExec, "checker should return false as there is no name to renew");
        assertEq(execPayload, bytes("no names to renew"), "checker should return false as there is no name to renew");
    }

    /// @dev Test `srens.checker()`'s returns false when the gas price is too high.
    function testFork_checker_failIfGasPriceTooHigh() external {
        // Subscribe as `scoopy` for `name`.
        vm.startPrank(scoopy, scoopy);
        srens.subscribe(name);

        // Wait for `name` to be in its grace period.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));
        vm.warp(expiresAt - 80 days);

        (bool canExec, bytes memory execPayload) = srens.checker(scoopy);
        assertFalse(canExec, "checker function should return false as `name` is not expired");
        assertEq(
            execPayload, bytes("no names to renew"), "checker function should return false as `name` is not expired"
        );
    }
}
