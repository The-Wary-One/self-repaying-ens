// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { SelfRepayingENS } from "src/SelfRepayingENS.sol";
import { Toolbox } from "script/Toolbox.s.sol";

contract DeploySRENS is Script {

    event log_named_address(string key, address val);

    /// @dev Deploy the contract on the target chain.
    function run() external returns (SelfRepayingENS) {
        // Get the config.
        Toolbox toolbox = new Toolbox();
        Toolbox.Config memory config = toolbox.getConfig();

        vm.startBroadcast();

        // Deploy the SRENS contract.
        SelfRepayingENS srens = new SelfRepayingENS(
            config.alchemist,
            config.alETHPool,
            config.curveCalc,
            config.controller,
            config.registrar,
            config.gelatoOps
        );

        vm.stopBroadcast();

        emit log_named_address("Contract deployed to", address(srens));

        return srens;
    }
}
