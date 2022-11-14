// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { Toolbox } from "script/Toolbox.s.sol";
import {
    SelfRepayingENS,
    LibDataTypes,
    Ops
} from "src/SelfRepayingENS.sol";

contract ToolboxLocal is Toolbox {

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {
        require(block.chainid == 1, "Script should be run on a mainnet fork");
    }

    /// @dev Get the Gelato module data.
    function getResolveData(SelfRepayingENS srens, string memory name, address subscriber) public returns (LibDataTypes.ModuleData memory) {
        bytes32 resolverHash = keccak256(abi.encode(
            address(srens),
            abi.encodeCall(srens.checker, (name, subscriber))
        ));

        LibDataTypes.Module[] memory modules = new LibDataTypes.Module[](1);
        modules[0] = LibDataTypes.Module.RESOLVER;
        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(resolverHash);

        return LibDataTypes.ModuleData({ modules: modules, args: args });
    }
}
