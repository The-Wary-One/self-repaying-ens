// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../../src/SelfRepayingENS.sol";

/// @dev This indirection allows us to expose internal functions.
contract SelfRepayingENSHarness is SelfRepayingENS {
    constructor(
        ETHRegistrarController _controller,
        BaseRegistrarImplementation _registrar,
        Automate _gelatoAutomate,
        IAlchemistV2 _alchemist,
        ICurveStableSwapNG _alETHPool,
        IWETH9 _weth
    ) SelfRepayingENS(_controller, _registrar, _gelatoAutomate, _alchemist, _alETHPool, _weth) {}

    /* --- EXPOSED INTERNAL FUNCTIONS --- */

    function exposed_getVariableMaxGasPrice(int256 expiredDuration) external pure returns (uint256) {
        return _getVariableMaxGasPrice(expiredDuration);
    }
}
