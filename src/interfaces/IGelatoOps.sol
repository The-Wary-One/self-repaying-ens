// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

/// @dev Gelato Ops interface duplication to compile in a newer Solidity version.
interface IGelatoOps {

    function gelato() external view returns (address payable);
    function getFeeDetails() external view returns (uint256, address);

    function createTaskNoPrepayment(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData,
        address _feeToken
    ) external returns (bytes32 task);
    function cancelTask(bytes32 task) external;

    function exec(
        uint256 _txFee,
        address _feeToken,
        address _taskCreator,
        bool _useTaskTreasuryFunds,
        bool _revertOnFailure,
        bytes32 _resolverHash,
        address _execAddress,
        bytes calldata _execData
    ) external;
}
