// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";

import {Whitelist} from "../lib/alchemix/src/utils/Whitelist.sol";
import {AlETHRouter, DeployAlETHRouter} from "../lib/aleth-router/script/DeployAlETHRouter.s.sol";

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

    /// @dev Deploy the AlETHRouter contract on the local chain.
    function deployRouter() public returns (AlETHRouter) {
        // Get the config.
        Toolbox.Config memory config = getConfig();

        // Deploy the router contract.
        DeployAlETHRouter deployer = new DeployAlETHRouter();
        return deployer.deploy(config.alchemist, config.alETHPool, config.curveCalc);
    }

    /// @dev Deploy the SRENS contract for tests.
    /// @dev **_NOTE:_** The AlETHRouter MUST be deployed BEFORE calling this.
    function deployTestSRENS() external returns (SelfRepayingENS) {
        // Get the config.
        Toolbox.Config memory config = getConfig();

        // Deploy the srens contract.
        // FIXME: Why does it work for the router but not for this ??? We broadcast in both !
        //DeploySRENS deployer = new DeploySRENS();
        //return deployer.deploy(
        //    config.router,
        //    config.controller,
        //    config.registrar,
        //    config.gelatoOps
        //);
        SelfRepayingENS srens = new SelfRepayingENS(
            config.router,
            config.controller,
            config.registrar,
            config.gelatoOps
        );

        return srens;
    }

    /// @dev Deploy the AlETHRouter contract for tests.
    function deployTestRouter() external {
        // Deploy the router contract.
        AlETHRouter router = deployRouter();
        // Override the config.
        _config.router = router;
        // Get the config.
        Toolbox.Config memory config = getConfig();
        // Add it to the alchemist whitelist.
        Whitelist whitelist = Whitelist(config.alchemist.whitelist());
        vm.prank(whitelist.owner());
        whitelist.add(address(router));
        require(whitelist.isWhitelisted(address(router)));
    }
}
