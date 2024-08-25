// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script} from "../lib/forge-std/src/Script.sol";

import {DeploySRENS} from "./DeploySRENS.s.sol";
import {Toolbox} from "./Toolbox.s.sol";

import {LibDataTypes, SelfRepayingENS} from "../src/SelfRepayingENS.sol";

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
        moduleData = LibDataTypes.ModuleData({modules: new LibDataTypes.Module[](2), args: new bytes[](2)});

        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;
        moduleData.modules[1] = LibDataTypes.Module.PROXY;

        moduleData.args[0] = abi.encode(address(srens), abi.encodeCall(srens.checker, (subscriber)));
        moduleData.args[1] = bytes("");
    }

    /// @dev Deploy the SRENS contract for tests.
    function deployTestSRENS() external returns (SelfRepayingENS) {
        // Get the config.
        Toolbox.Config memory config = getConfig();

        SelfRepayingENS srens = new SelfRepayingENS(
            config.controller, config.registrar, config.gelatoAutomate, config.alchemist, config.alETHPool, config.weth
        );

        return srens;
    }
}
