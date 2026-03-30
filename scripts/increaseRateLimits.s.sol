// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract IncreaseRateLimits is Script, L2Constants, GnosisHelpers {

    uint256 constant NEW_LIMIT = 10_000 ether;
    uint256 constant NEW_WINDOW = 4 hours;

    function run() public {
        _generateMainnetJson();
        _generateScrollJson();
        _generateOpJson();
    }

    function _generateMainnetJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](1);
        config[0] = LayerZeroHelpers._getRateLimitConfig(SCROLL.L2_EID, NEW_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory json = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), inboundData, true)));
        vm.writeJson(json, "./output/mainnet-increase-rate-limits.json");
    }

    function _generateScrollJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](2);
        config[0] = LayerZeroHelpers._getRateLimitConfig(L1_EID, NEW_LIMIT, NEW_WINDOW);
        config[1] = LayerZeroHelpers._getRateLimitConfig(OP.L2_EID, NEW_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory json = _getGnosisHeader(SCROLL.CHAIN_ID, SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(SCROLL.L2_OFT), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(SCROLL.L2_OFT), inboundData, true)));
        vm.writeJson(json, "./output/scroll-increase-rate-limits.json");
    }

    function _generateOpJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](1);
        config[0] = LayerZeroHelpers._getRateLimitConfig(SCROLL.L2_EID, NEW_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory json = _getGnosisHeader(OP.CHAIN_ID, OP.L2_CONTRACT_CONTROLLER_SAFE);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(OP.L2_OFT), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(OP.L2_OFT), inboundData, true)));
        vm.writeJson(json, "./output/op-increase-rate-limits.json");
    }
}
