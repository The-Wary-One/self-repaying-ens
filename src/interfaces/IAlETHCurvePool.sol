// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IAlETHCurvePool {

    function get_dy(int128 i, int128 j, uint256 amount) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 amount, uint256 minAmount) external payable returns (uint256);
}
