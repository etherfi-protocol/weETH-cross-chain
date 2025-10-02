// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../contracts/PairwiseRateLimiter.sol";

contract GenerateBlastRateLimitTransactions is Script, L2Constants, GnosisHelpers {
    using LayerZeroHelpers for *;
    
    uint256 constant RESTRICTED_LIMIT = 50 ether;
    uint256 constant RESTRICTED_WINDOW = 12 hours;

    function run() public {
        ConfigPerL2 memory blastConfig = BLAST;
        
        // Create rate limit configurations for all L2s
        PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);
        PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);

        for (uint256 j = 0; j < L2s.length; j++) {
            if (keccak256(abi.encodePacked(L2s[j].NAME)) == keccak256(abi.encodePacked("blast"))) { 
                outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L1_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
            } else {
                outboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
                inboundConfig[j] = LayerZeroHelpers._getRateLimitConfig(L2s[j].L2_EID, RESTRICTED_LIMIT, RESTRICTED_WINDOW);
            }
        }

        // Generate Gnosis transaction JSON with individual transactions
        string memory transactionJson = _getGnosisHeader(blastConfig.CHAIN_ID, blastConfig.L2_CONTRACT_CONTROLLER_SAFE);
        
        // Transaction 1: setOutboundRateLimits
        string memory setOutboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", outboundConfig));
        transactionJson = string(abi.encodePacked(transactionJson, _getGnosisTransaction(addressToHex(blastConfig.L2_OFT), setOutboundData, false)));
        
        // Transaction 2: setInboundRateLimits
        string memory setInboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", inboundConfig));
        transactionJson = string(abi.encodePacked(transactionJson, _getGnosisTransaction(addressToHex(blastConfig.L2_OFT), setInboundData, false)));
        
        // Transaction 3: revokeRole (MINTER_ROLE)
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        string memory revokeMinterData = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", MINTER_ROLE, blastConfig.L2_SYNC_POOL));
        transactionJson = string(abi.encodePacked(transactionJson, _getGnosisTransaction(addressToHex(blastConfig.L2_OFT), revokeMinterData, false)));
        
        // Transaction 4: setMinSyncAmount
        string memory setMinSyncData = iToHex(abi.encodeWithSignature("setMinSyncAmount(address,uint256)", ETH_ADDRESS, 0));
        transactionJson = string(abi.encodePacked(transactionJson, _getGnosisTransaction(addressToHex(blastConfig.L2_SYNC_POOL), setMinSyncData, true)));
        
        vm.writeJson(transactionJson, "./output/blast-rate-limit-update.json");
        
        console.log("Generated Blast rate limit transaction JSON:");
        console.log("File: ./output/blast-rate-limit-update.json");
        console.log("Rate limit:", RESTRICTED_LIMIT);
        console.log("Rate limit window:", RESTRICTED_WINDOW);
        console.log("Number of transactions: 4");
    }

}
