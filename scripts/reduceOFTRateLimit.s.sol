// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract ReduceRateLimits is Script, L2Constants, GnosisHelpers {
    using LayerZeroHelpers for *;
    
    string[] public targetChains = ["blast", "mode", "morph", "sonic", "zksync"];
    
    uint256 constant RESTRICTED_LIMIT = 50 ether;
    uint256 constant RESTRICTED_WINDOW = 12 hours;

    function run() public {
        for (uint256 i = 0; i < L2s.length; i++) {
            // Set all pathways on deprecated chains to have the restricted rate limit
            if (_isTargetChain(L2s[i].NAME)) {
                PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);
                PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);

                for (uint256 j = 0; j < L2s.length; j++) {
                    if (j == i) {
                        // we need to set the rate limit for mainnet as well so use the self loop to do so
                        outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                        inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                    } else {
                        outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                        inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                    }
                }

                string memory setOutboundDataString = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", outboundConfig));
                string memory setInboundDataString = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", inboundConfig));

                string memory reduceRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID, L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
                reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setOutboundDataString, false)));
                reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setInboundDataString, true)));
                vm.writeJson(reduceRateLimitJson, string.concat("./output/", L2s[i].NAME, "-ReduceAllPathways.json"));
            }

            // if the chain is not a chain to be deprecated, only update the pathways to the deprecated chains
            if (!_isTargetChain(L2s[i].NAME)) {
                PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig = new PairwiseRateLimiter.RateLimitConfig[](targetChains.length);
                PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig = new PairwiseRateLimiter.RateLimitConfig[](targetChains.length);
                
                uint256 index = 0;
                for(uint256 j = 0; j < L2s.length; j++) {
                    if (_isTargetChain(L2s[j].NAME)) {
                        outboundConfig[index] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                        inboundConfig[index] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                        index++;
                    }
                }

                string memory setOutboundDataString = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", outboundConfig));
                string memory setInboundDataString = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", inboundConfig));

                string memory reduceRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID, L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
                reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setOutboundDataString, false)));
                reduceRateLimitJson = string(abi.encodePacked(reduceRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), setInboundDataString, true)));
                vm.writeJson(reduceRateLimitJson, string.concat("./output/", L2s[i].NAME, "-ReducePathways.json"));

                // we need to do a one time generation for mainnet as well, so just do it on the loop over base
                if (keccak256(abi.encodePacked(L2s[i].NAME)) == keccak256(abi.encodePacked("base"))) {
                    string memory reduceRateLimitMainnetJson = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);
                    reduceRateLimitMainnetJson = string(abi.encodePacked(reduceRateLimitMainnetJson, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), setOutboundDataString, false)));
                    reduceRateLimitMainnetJson = string(abi.encodePacked(reduceRateLimitMainnetJson, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), setInboundDataString, true)));
                    vm.writeJson(reduceRateLimitMainnetJson, string.concat("./output/", "Mainnet-ReducePathways.json"));
                }
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
