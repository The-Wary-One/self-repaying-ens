// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script} from "../lib/forge-std/src/Script.sol";

import {Toolbox} from "./Toolbox.s.sol";

import {
    BaseRegistrarImplementation,
    ETHRegistrarController,
    IAlchemistV2,
    ICurveStableSwapNG,
    IWETH9,
    Automate,
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
            config.controller, config.registrar, config.gelatoAutomate, config.alchemist, config.alETHPool, config.weth
        );
    }

    /// @dev Deploy the contract.
    function deploy(
        ETHRegistrarController controller,
        BaseRegistrarImplementation registrar,
        Automate gelatoAutomate,
        IAlchemistV2 alchemist,
        ICurveStableSwapNG alETHPool,
        IWETH9 weth
    ) public returns (SelfRepayingENS) {
        // Deploy the SRENS contract.
        vmSafe.broadcast();
        SelfRepayingENS srens = new SelfRepayingENS(controller, registrar, gelatoAutomate, alchemist, alETHPool, weth);

        return srens;
    }
}
