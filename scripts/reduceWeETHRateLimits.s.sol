// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract ReduceWeETHRateLimits is Script, L2Constants, GnosisHelpers {

    uint256 constant SCROLL_LIMIT = 100 ether;
    uint256 constant OP_LIMIT = 3_000 ether;
    uint256 constant NEW_WINDOW = 4 hours;

    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function run() public {
        _generateMainnetJson();
        _generateScrollJson();
        _generateOpJson();
    }

    function _generateMainnetJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](2);
        config[0] = LayerZeroHelpers._getRateLimitConfig(SCROLL.L2_EID, SCROLL_LIMIT, NEW_WINDOW);
        config[1] = LayerZeroHelpers._getRateLimitConfig(OP.L2_EID, OP_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory json = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), inboundData, true)));
        vm.writeJson(json, "./output/mainnet-reduce-rate-limits.json");
    }

    function _generateScrollJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](2);
        config[0] = LayerZeroHelpers._getRateLimitConfig(L1_EID, SCROLL_LIMIT, NEW_WINDOW);
        config[1] = LayerZeroHelpers._getRateLimitConfig(OP.L2_EID, SCROLL_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory revokeData = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", MINTER_ROLE, SCROLL.L2_SYNC_POOL));

        string memory json = _getGnosisHeader(SCROLL.CHAIN_ID, SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(SCROLL.L2_OFT), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(SCROLL.L2_OFT), inboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(SCROLL.L2_OFT), revokeData, true)));
        vm.writeJson(json, "./output/scroll-reduce-rate-limits.json");
    }

    function _generateOpJson() internal {
        PairwiseRateLimiter.RateLimitConfig[] memory config = new PairwiseRateLimiter.RateLimitConfig[](2);
        config[0] = LayerZeroHelpers._getRateLimitConfig(SCROLL.L2_EID, SCROLL_LIMIT, NEW_WINDOW);
        config[1] = LayerZeroHelpers._getRateLimitConfig(L1_EID, OP_LIMIT, NEW_WINDOW);

        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", config));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", config));

        string memory json = _getGnosisHeader(OP.CHAIN_ID, OP.L2_CONTRACT_CONTROLLER_SAFE);
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(OP.L2_OFT), outboundData, false)));
        json = string(abi.encodePacked(json, _getGnosisTransaction(addressToHex(OP.L2_OFT), inboundData, true)));
        vm.writeJson(json, "./output/op-reduce-rate-limits.json");
    }
}
