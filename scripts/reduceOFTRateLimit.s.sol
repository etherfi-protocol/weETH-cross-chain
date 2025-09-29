// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract ReduceRateLimits is Script, Constants, GnosisHelpers {
    using LayerZeroHelpers for *;
    
    string[] public targetChains = ["blast", "mode", "morph", "sonic", "zksync"];
    
    uint256 constant NEW_LIMIT = 50 ether;
    uint256 constant NEW_WINDOW = 12 hours;

    function run() public {
        for (uint256 i = 0; i < L2s.length; i++) {
            console.log("Processing rate limit updates for:", L2s[i].NAME);
            
            // Create outbound rate limit config
            PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);
            // Create inbound rate limit config  
            PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);
            
            for (uint256 j = 0; j < L2s.length; j++) {
                if (i == j) {
                    // Mainnet peer - use normal limits for both inbound and outbound
                    outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, LIMIT, WINDOW);
                    inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, LIMIT, WINDOW);
                } else {
                    // Check if current chain is deprecated
                    if (_isTargetChain(L2s[i].NAME)) {
                        // Deprecated chain: all inbound and outbound should be restricted
                        outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, NEW_LIMIT, NEW_WINDOW);
                        inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, NEW_LIMIT, NEW_WINDOW);
                    } else {
                        // Non-deprecated chain: only restrict to deprecated chains
                        if (_isTargetChain(L2s[j].NAME)) {
                            // Target deprecated chains with restricted limits
                            outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, NEW_LIMIT, NEW_WINDOW);
                            inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, NEW_LIMIT, NEW_WINDOW);
                        } else {
                            // Non-deprecated chains use normal limits
                            outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, LIMIT, WINDOW);
                            inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, LIMIT, WINDOW);
                        }
                    }
                }
            }
            
            // Create transaction data for both outbound and inbound
            string memory setOutboundDataString = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", outboundConfig));
            string memory setInboundDataString = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", inboundConfig));

            // Create gnosis transaction with both outbound and inbound rate limit data
            string memory reduceRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID, L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
            reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setOutboundDataString, false)));
            reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setInboundDataString, true)));
            vm.writeJson(reduceRateLimitJson, string.concat("./output/", L2s[i].NAME, "-RateLimitReduction.json"));
            
            console.log("Generated rate limit reduction transaction for:", L2s[i].NAME);
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
