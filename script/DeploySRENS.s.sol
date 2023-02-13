// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";

import {Toolbox} from "./Toolbox.s.sol";

import {
    BaseRegistrarImplementation,
    ETHRegistrarController,
    IAlchemistV2,
    ICurveCalc,
    ICurvePool,
    Ops,
    SelfRepayingENS
} from "../src/SelfRepayingENS.sol";

contract DeploySRENS is Script {
    /// @dev Deploy the contract on the target chain.
    function run() external returns (SelfRepayingENS) {
        // Get the config.
        Toolbox toolbox = new Toolbox();
        Toolbox.Config memory config = toolbox.getConfig();

        // Deploy the contract.
        return deploy(
            config.controller, config.registrar, config.gelatoOps, config.alchemist, config.alETHPool, config.curveCalc
        );
    }

    /// @dev Deploy the contract.
    function deploy(
        ETHRegistrarController controller,
        BaseRegistrarImplementation registrar,
        Ops gelatoOps,
        IAlchemistV2 alchemist,
        ICurvePool alETHPool,
        ICurveCalc curveCalc
    ) public returns (SelfRepayingENS) {
        // Deploy the SRENS contract.
        vmSafe.broadcast();
        SelfRepayingENS srens = new SelfRepayingENS(
            controller,
            registrar,
            gelatoOps,
            alchemist,
            alETHPool,
            curveCalc
        );

        return srens;
    }
}
