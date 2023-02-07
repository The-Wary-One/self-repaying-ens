// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";

import {Toolbox} from "./Toolbox.s.sol";

import {
    AlETHRouter,
    BaseRegistrarImplementation,
    ETHRegistrarController,
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
        return deploy(config.router, config.controller, config.registrar, config.gelatoOps);
    }

    /// @dev Deploy the contract.
    function deploy(
        AlETHRouter router,
        ETHRegistrarController controller,
        BaseRegistrarImplementation registrar,
        Ops gelatoOps
    ) public returns (SelfRepayingENS) {
        // Deploy the SRENS contract.
        vmSafe.broadcast();
        SelfRepayingENS srens = new SelfRepayingENS(
            router,
            controller,
            registrar,
            gelatoOps
        );

        return srens;
    }
}
