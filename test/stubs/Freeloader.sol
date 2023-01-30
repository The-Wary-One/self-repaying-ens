// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../../src/SelfRepayingENS.sol";

/// @dev A contract that tries to renew its names using a `SelfRepyaingENS` user's funds.
contract Freeloader {
    SelfRepayingENS immutable srens;
    Ops public immutable gelatoOps;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(SelfRepayingENS _srens, Ops _gelatoOps) {
        srens = _srens;
        gelatoOps = _gelatoOps;
    }

    function subscribe(string memory name, address subscriber) external returns (bytes32 taskId) {
        taskId = gelatoOps.createTask(
            address(srens), abi.encode(srens.renew.selector), _getModuleData(subscriber, name), ETH
        );
    }

    function checker(address subscriber, string memory name)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        return (true, abi.encodeCall(srens.renew, (name, subscriber)));
    }

    function _getModuleData(address subscriber, string memory name)
        public
        view
        returns (LibDataTypes.ModuleData memory moduleData)
    {
        moduleData = LibDataTypes.ModuleData({modules: new LibDataTypes.Module[](1), args: new bytes[](1)});

        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;

        moduleData.args[0] = abi.encode(address(this), abi.encodeCall(this.checker, (subscriber, name)));
    }
}
