// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {TestBase} from "../TestBase.sol";
import {SelfRepayingENSHarness} from "./harnesses/SelfRepayingENSHarness.sol";

contract GetVariableMaxGasPriceTests is TestBase {
    SelfRepayingENSHarness srensHarness;

    function setUp() public override {
        // We need the `GelatoOps` contract to be deployed to deploy `SelfRepayinsENS`.
        super.setUp();

        srensHarness = new SelfRepayingENSHarness(
            config.controller,
            config.registrar,
            config.gelatoAutomate,
            config.alchemist,
            config.alETHPool,
            config.curveCalc
        );
    }

    /// @dev Test the internal function `srens._getVariableMaxGasPrice()` returns the correct gas price limit.
    function test_getVariableMaxGasPrice() external {
        assertEq(
            srensHarness.exposed_getVariableMaxGasPrice(-90 days),
            0,
            "We don't want to try to renew before 90 days before expiry"
        );
        assertEq(
            srensHarness.exposed_getVariableMaxGasPrice(-80 days),
            10 gwei,
            "80 days before expiry we want to renew at a max gas price of 10 gwei"
        );
        assertApproxEqAbs(
            srensHarness.exposed_getVariableMaxGasPrice(-40 days),
            50 gwei,
            1 gwei,
            "40 days before expiry we want to renew at a max gas price of 50 gwei"
        );
        assertApproxEqAbs(
            srensHarness.exposed_getVariableMaxGasPrice(-10 days),
            80 gwei,
            2 gwei,
            "10 days before expiry we want to renew at a max gas price of around 80 gwei"
        );
        assertApproxEqAbs(
            srensHarness.exposed_getVariableMaxGasPrice(-2 days),
            125 gwei,
            1 gwei,
            "2 days before expiry we want to renew at a max gas price of around 125 gwei"
        );
        assertEq(
            srensHarness.exposed_getVariableMaxGasPrice(1),
            type(uint256).max,
            "Since expiry we remove the gas price limit"
        );
    }
}
