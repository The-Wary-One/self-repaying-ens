// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";

import {DeploySRENS} from "./DeploySRENS.s.sol";
import {Toolbox} from "./Toolbox.s.sol";

import {LibDataTypes, Ops, SelfRepayingENS} from "../src/SelfRepayingENS.sol";

contract ToolboxLocal is Toolbox {
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {
        require(block.chainid == 1, "Script should be run on a mainnet fork");
    }

    /// @dev Get the Gelato module data.
    function getModuleData(SelfRepayingENS srens, address subscriber)
        public
        pure
        returns (LibDataTypes.ModuleData memory moduleData)
    {
        moduleData = LibDataTypes.ModuleData({modules: new LibDataTypes.Module[](1), args: new bytes[](1)});

        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;

        moduleData.args[0] = abi.encode(address(srens), abi.encodeCall(srens.checker, (subscriber)));
    }

    /// @dev Deploy the SRENS contract for tests.
    function deployTestSRENS() external returns (SelfRepayingENS) {
        // Get the config.
        Toolbox.Config memory config = getConfig();

        SelfRepayingENS srens = new SelfRepayingENS(
            config.controller,
            config.registrar,
            config.gelatoOps,
            config.alchemist,
            config.alETHPool,
            config.curveCalc
        );

        return srens;
    }
}
