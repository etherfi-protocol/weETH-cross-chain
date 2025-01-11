// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockExchangeRateProvider {

    function getConversionAmount(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        return (amountIn * 95 / 100);
    }

}
