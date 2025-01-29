// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {L2ExchangeRateProviderUpgradeable} from "./layerzero-base/L2ExchangeRateProviderUpgradeable.sol";
import {IAggregatorV3} from "../../interfaces/IAggregatorV3.sol";

contract EtherfiL2ExchangeRateProvider is L2ExchangeRateProviderUpgradeable {
    error EtherfiL2ExchangeRateProvider__InvalidRate();

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    /**
     * @dev Internal function to get rate and last updated time from a rate oracle
     * @param rateOracle Rate oracle contract
     * @return rate The exchange rate in 1e18 precision
     * @return lastUpdated Last updated time
     */
    function _getRateAndLastUpdated(address rateOracle, address)
        internal
        view
        override
        returns (uint256 rate, uint256 lastUpdated)
    {
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(rateOracle).latestRoundData();

        if (answer <= 0) revert EtherfiL2ExchangeRateProvider__InvalidRate();

        // adjust 'answer' based on Oracle feed's precision to have 1e18 precision
        // rate * 1e18 /  10**oracle.decimals()
        uint8 oracleDecimals = IAggregatorV3(rateOracle).decimals();
        return (uint256(uint256(answer) * 1e18 / 10**oracleDecimals), updatedAt);
    }
}
