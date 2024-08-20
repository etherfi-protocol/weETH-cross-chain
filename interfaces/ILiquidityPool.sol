
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquidityPool {
    function depositToRecipient(uint256 _amount) external returns (uint256);
}
