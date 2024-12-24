// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "../contracts/PairwiseRateLimiter.sol";

import "../contracts/EtherfiOFTUpgradeable.sol";
import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";


// forge script scripts/RaiseRateLimits.s.sol:RaiseRateLimits
contract RaiseRateLimits is Script, Constants, LayerZeroHelpers, GnosisHelpers {

    function run() public {
        PairwiseRateLimiter.RateLimitConfig[] memory rateLimitConfigs = new PairwiseRateLimiter.RateLimitConfig[](1);
        string memory l1OftAdapterString = iToHex(abi.encodePacked(L1_OFT_ADAPTER));
        string memory swellOftString = iToHex(abi.encodePacked(SWELL.L2_OFT));

        // lift outbound for mainnet
        rateLimitConfigs[0] = _getRateLimitConfig(SWELL.L2_EID, 30_000 ether, WINDOW);
        string memory setOutboundRateLimitData =  iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs));
        string memory MainnetJson = _getGnosisHeader("1");
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setOutboundRateLimitData, true));
        vm.writeJson(MainnetJson, string.concat("./output/Mainnet-RateLimitIncrease.json"));

        // lift inbound for swell
        rateLimitConfigs[0] = _getRateLimitConfig(L1_EID, 30_000 ether, WINDOW);
        string memory setInboundRateLimitData =  iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs));
        string memory SwellJson = _getGnosisHeader(SWELL.CHAIN_ID);
        SwellJson = string.concat(SwellJson, _getGnosisTransaction(swellOftString, setInboundRateLimitData, true));
        vm.writeJson(SwellJson, string.concat("./output/Swell-RateLimitIncrease.json"));


        // reset rate limits for mainnet
        rateLimitConfigs[0] = _getRateLimitConfig(SWELL.L2_EID, LIMIT, WINDOW);
        setOutboundRateLimitData =  iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs));
        MainnetJson = _getGnosisHeader("1");
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setOutboundRateLimitData, true));
        vm.writeJson(MainnetJson, string.concat("./output/Mainnet-RateLimitReset.json"));

        // reset rate limits for swell
        rateLimitConfigs[0] = _getRateLimitConfig(L1_EID, LIMIT, WINDOW);
        setInboundRateLimitData =  iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs));
        SwellJson = _getGnosisHeader(SWELL.CHAIN_ID);
        SwellJson = string.concat(SwellJson, _getGnosisTransaction(swellOftString, setInboundRateLimitData, true));
        vm.writeJson(SwellJson, string.concat("./output/Swell-RateLimitReset.json"));

    }
}
