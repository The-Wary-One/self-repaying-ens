// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "src/SelfRepayingENS.sol";

/// @dev This indirection allows us to expose internal functions.
contract SelfRepayingENSStub is SelfRepayingENS {

    constructor(
        IAlchemistV2 _alchemist,
        ICurveAlETHPool _alETHPool,
        ICurveCalc _curveCalc,
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        IGelatoOps _gelatoOps
    ) SelfRepayingENS(
            _alchemist,
            _alETHPool,
            _curveCalc,
            _controller,
            _registrar,
            _gelatoOps
    ) {}

    /* --- EXPOSED INTERNAL FUNCTIONS --- */

    function publicGetVariableMaxBaseFee(int256 expiredDuration) external pure returns (uint256) {
        return _getVariableMaxBaseFee(expiredDuration);
    }
}
