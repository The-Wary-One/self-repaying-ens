// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

/// @dev Gelato Ops interface duplication to compile in a newer Solidity version.
interface IGelatoOps {

    function gelato() external view returns (address payable);
    function getFeeDetails() external view returns (uint256, address);
    function getResolverHash(
        address _resolverAddress,
        bytes memory _resolverData
    ) external pure returns (bytes32);
    function getTaskId(
        address _taskCreator,
        address _execAddress,
        bytes4 _selector,
        bool _useTaskTreasuryFunds,
        address _feeToken,
        bytes32 _resolverHash
    ) external pure returns (bytes32);

    function createTask(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData
    ) external returns (bytes32 task);
    function createTaskNoPrepayment(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData,
        address _feeToken
    ) external returns (bytes32 task);
    function cancelTask(bytes32 task) external;
}
