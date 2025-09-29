// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract ReduceRateLimits is Script, Constants, GnosisHelpers {
    using LayerZeroHelpers for *;
    
    // Target chains for rate limit reduction
    string[] public targetChains = ["blast", "mode", "morph", "sonic", "zksync"];
    
    // New rate limit: 50 weETH per 12 hours
    uint256 constant NEW_LIMIT = 50 ether;
    uint256 constant NEW_WINDOW = 12 hours;

    function run() public {
        for (uint256 i = 0; i < L2s.length; i++) {
            // Check if this L2 is in our target list
            if (_isTargetChain(L2s[i].NAME)) {
                console.log("Processing rate limit reduction for:", L2s[i].NAME);
                
                // Create rate limit transaction to update rate limits for all peers
                PairwiseRateLimiter.RateLimitConfig[] memory rateLimitConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);
                for (uint256 j = 0; j < L2s.length; j++) {
                    if (i == j) {
                        // Currently on the L2 we are updating rate limits for, set mainnet config here instead
                        rateLimitConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, NEW_LIMIT, NEW_WINDOW);
                    } else {
                        rateLimitConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, NEW_LIMIT, NEW_WINDOW);
                    }
                }
                
                string memory setRateLimitDataString = iToHex(abi.encodeWithSignature("setRateLimits((uint32,uint256,uint256)[])", rateLimitConfig));

                // Create gnosis transaction with rate limit data
                string memory reduceRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID, L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
                reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setRateLimitDataString, true)));
                vm.writeJson(reduceRateLimitJson, string.concat("./output/", L2s[i].NAME, "-RateLimitReduction.json"));
                
                console.log("Generated rate limit reduction transaction for:", L2s[i].NAME);
            }
        }
    }
    
    function _isTargetChain(string memory chainName) internal pure returns (bool) {
        bytes32 nameHash = keccak256(abi.encodePacked(chainName));
        return (
            nameHash == keccak256(abi.encodePacked("blast")) ||
            nameHash == keccak256(abi.encodePacked("mode")) ||
            nameHash == keccak256(abi.encodePacked("morph")) ||
            nameHash == keccak256(abi.encodePacked("sonic")) ||
            nameHash == keccak256(abi.encodePacked("zksync"))
        );
    }
}
