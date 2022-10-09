// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "src/SelfRepayingENSRenewals.sol";

/// @dev This indirection allows us to expose internal functions.
contract SelfRepayingENSRenewalsStub is SelfRepayingENSRenewals {

    constructor(
        IAlchemistV2 _alchemist,
        ICurveAlETHPool _alETHPool,
        ICurveCalc _curveCalc,
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        IGelatoOps _gelatoOps
    ) SelfRepayingENSRenewals(
            _alchemist,
            _alETHPool,
            _curveCalc,
            _controller,
            _registrar,
            _gelatoOps
    ) {}

    /* --- EXPOSED INTERNAL FUNCTIONS --- */

    function publicGetAlETHToMint(uint256 neededETH) public view returns (uint256) {
        return _getAlETHToMint(neededETH);
    }

    function publicGetVariableMaxBaseFee(int256 expiredDuration) external pure returns (uint256) {
        return _getVariableMaxBaseFee(expiredDuration);
    }
}
