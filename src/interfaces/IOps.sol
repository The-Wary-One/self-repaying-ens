// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.16;

interface IOps {

    function getFeeDetails() external view returns (uint256, address);

    function createTask(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData
    ) external returns (bytes32 task);
}
