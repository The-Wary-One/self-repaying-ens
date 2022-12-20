// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../../src/SelfRepayingENS.sol";

/// @dev A contract that tries to renew its names using a `SelfRepyaingENS` user's funds.
contract Freeloader {
    SelfRepayingENS immutable srens;
    Ops public immutable gelatoOps;
    address immutable subscriber;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(
        SelfRepayingENS _srens,
        Ops _gelatoOps,
        address _subscriber
    ) {
        srens = _srens;
        gelatoOps = _gelatoOps;
        subscriber = _subscriber;
    }

    function subscribe(string memory name) external returns (bytes32 task) {
        LibDataTypes.ModuleData memory moduleData = LibDataTypes.ModuleData({modules: new LibDataTypes.Module[](1), args: new bytes[](1)});
        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;
        moduleData.args[0] = abi.encode(address(srens), abi.encodeCall(srens.checker, (name, subscriber)));

        task = gelatoOps.createTask(
            address(srens), abi.encode(srens.renew.selector), moduleData, ETH
        );
    }
}
