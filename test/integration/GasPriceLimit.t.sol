// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {TestBase} from "../TestBase.sol";

import {SelfRepayingENS} from "../../src/SelfRepayingENS.sol";

contract GetVariableMaxGasPriceTests is TestBase {
    /// @dev Test `srens.getVariableMaxGasPrice()` returns the correct gas price limit for `name`.
    function testFork_getVariableMaxGasPrice() external {
        // Warp to 90 days before expiry.
        bytes32 labelHash = keccak256(bytes(name));
        uint256 expiresAt = config.registrar.nameExpires(uint256(labelHash));

        vm.warp(expiresAt - 90 days);
        assertEq(srens.getVariableMaxGasPrice(name), 0, "Before being expired - 90 days, it should return 0");

        // Wait for `name` to be in its 90 days renew period.
        vm.warp(expiresAt - 40 days);

        assertApproxEqAbs(
            srens.getVariableMaxGasPrice(name),
            50 gwei,
            1 gwei,
            "40 days before expiry we want to renew at a max gas price of 50 gwei"
        );
    }
}
