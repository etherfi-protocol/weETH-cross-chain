// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IL2ExchangeRateProvider {
     /**
     * @dev Rate parameters for a token
     * @param rateOracle Rate oracle contract, providing the exchange rate
     * @param depositFee Deposit fee, in 1e18 precision (e.g. 1e16 for 1% fee)
     * @param freshPeriod Fresh period, in seconds
     */
    struct RateParameters {
        address rateOracle;
        uint64 depositFee;
        uint32 freshPeriod;
    }

    function getConversionAmount(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);
    function getConversionAmountUnsafe(address token, uint256 amountIn) external view returns (uint256 amountOut);
    function getRateParameters(address token) external view returns (RateParameters memory parameters);
    function setRateParameters(address token, address rateOracle, uint64 depositFee, uint32 freshPeriod) external;
}
