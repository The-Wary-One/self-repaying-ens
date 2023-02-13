// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../../../src/SelfRepayingENS.sol";

/// @dev This indirection allows us to expose internal functions.
contract SelfRepayingENSHarness is SelfRepayingENS {
    constructor(
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        Ops _gelatoOps,
        IAlchemistV2 _alchemist,
        ICurvePool _alETHPool,
        ICurveCalc _curveCalc
    ) SelfRepayingENS(_controller, _registrar, _gelatoOps, _alchemist, _alETHPool, _curveCalc) {}

    /* --- EXPOSED INTERNAL FUNCTIONS --- */

    function exposed_getVariableMaxGasPrice(int256 expiredDuration) external pure returns (uint256) {
        return _getVariableMaxGasPrice(expiredDuration);
    }
}
