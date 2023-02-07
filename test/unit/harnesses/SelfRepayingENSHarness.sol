// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {
    AlETHRouter,
    BaseRegistrarImplementation,
    ETHRegistrarController,
    Ops,
    SelfRepayingENS
} from "../../../src/SelfRepayingENS.sol";

/// @dev This indirection allows us to expose internal functions.
contract SelfRepayingENSHarness is SelfRepayingENS {
    constructor(
        AlETHRouter _router,
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        Ops _gelatoOps
    ) SelfRepayingENS(_router, _controller, _registrar, _gelatoOps) {}

    /* --- EXPOSED INTERNAL FUNCTIONS --- */

    function exposed_getVariableMaxGasPrice(int256 expiredDuration) external pure returns (uint256) {
        return _getVariableMaxGasPrice(expiredDuration);
    }
}
