// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Script, stdJson } from "forge-std/Script.sol";
import { WETHGateway } from "alchemix/WETHGateway.sol";
import { Whitelist } from "alchemix/utils/Whitelist.sol";
import {
    SelfRepayingENS,
    IAlchemistV2,
    ETHRegistrarController,
    BaseRegistrarImplementation,
    ICurveAlETHPool,
    ICurveCalc,
    IGelatoOps
} from "src/SelfRepayingENS.sol";

contract GetConfig is Script {

    using stdJson for string;

    // We must follow the alphabetical order of the json file.
    struct Config {
        IAlchemistV2 alchemist;
        ICurveAlETHPool alETHPool;
        ICurveCalc curveCalc;
        ETHRegistrarController controller;
        BaseRegistrarImplementation registrar;
        IGelatoOps gelatoOps;
        WETHGateway wethGateway;
        address gelato;
    }

    /// @dev Get the environment config.
    function run() external returns (Config memory) {
        // Get the deployed contracts addresses from the json config file.
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/externals.json");
        string memory json = vm.readFile(path);
        // Will panic if the network config is missing.
        bytes memory raw = json.parseRaw(string.concat("$.chainId.", vm.toString(block.chainid)));
        return abi.decode(raw, (Config));
    }
}
