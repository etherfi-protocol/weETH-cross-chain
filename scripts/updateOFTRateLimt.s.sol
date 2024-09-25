// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract SetRateLimits is Script, Constants, LayerZeroHelpers, GnosisHelpers {
    RateLimiter.RateLimitConfig[] public deploymentRateLimitConfigs;

    function run() public {

        for (uint256 i = 0; i < L2s.length; i++) {
            // Create rate limit transaction to update rate limits for all peers
            RateLimiter.RateLimitConfig[] memory rateLimitConfig = new RateLimiter.RateLimitConfig[](L2s.length);
            for (uint256 j = 0; j < L2s.length; j++) {
                if (i == j) {
                    // currently on the L2 we are updating rate limits for, set mainnet config here instead
                    rateLimitConfig[j] = _getRateLimitConfig(L1_EID, LIMIT, WINDOW);
                } else {
                    rateLimitConfig[j] = _getRateLimitConfig(L2s[j].L2_EID, LIMIT, WINDOW);
                }
            }
            string memory setRateLimitDataString = iToHex(abi.encodeWithSignature("setRateLimits((uint32,uint256,uint256)[])", rateLimitConfig));

            // Create gnosis transaction with rate limit data
            string memory UpdateRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID);
            UpdateRateLimitJson = string(abi.encodePacked(UpdateRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setRateLimitDataString, true)));
            vm.writeJson(UpdateRateLimitJson, string.concat("./output/", L2s[i].NAME, "-RateLimitIncrease.json"));
        }
    }
}
