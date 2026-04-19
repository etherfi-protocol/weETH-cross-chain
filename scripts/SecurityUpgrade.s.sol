// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import "../contracts/PairwiseRateLimiter.sol";
import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/GnosisHelpers.sol";

contract SecurityUpgrade is Script, L2Constants, GnosisHelpers {

    uint256 constant RESTRICTED_LIMIT = 20 ether;
    uint256 constant STANDARD_LIMIT = 2_000 ether;
    uint256 constant BASE_LIMIT = 10_000 ether;
    uint256 constant OP_LIMIT = 3_000 ether;
    uint256 constant RATE_WINDOW = 4 hours;

    uint32[] allL2Eids;
    uint256[] allL2Limits;

    function run() public {
        _setupPeers();

        _generateEthereumJson();

        // 14 chains to unpause + rate limits + DVN
        _generateL2Json(BASE, BASE_LIMIT, true);
        _generateL2Json(OP, OP_LIMIT, true);
        _generateL2Json(UNICHAIN, STANDARD_LIMIT, true);
        _generateL2Json(MONAD, STANDARD_LIMIT, true);
        _generateL2Json(LINEA, STANDARD_LIMIT, true);
        _generateL2Json(BERA, RESTRICTED_LIMIT, true);
        _generateL2Json(AVAX, RESTRICTED_LIMIT, true);
        _generateL2Json(INK, STANDARD_LIMIT, true);
        _generateL2Json(BNB, RESTRICTED_LIMIT, true);
        _generateL2Json(ZKSYNC, RESTRICTED_LIMIT, true);
        _generateL2Json(SONIC, RESTRICTED_LIMIT, true);
        _generateL2Json(PLASMA, STANDARD_LIMIT, true);
        _generateL2Json(HYPEREVM, STANDARD_LIMIT, true);

        // 6 chains: rate limits + DVN only (no unpause)
        _generateL2Json(BLAST, RESTRICTED_LIMIT, false);
        _generateL2Json(MODE, RESTRICTED_LIMIT, false);
        _generateL2Json(MORPH, RESTRICTED_LIMIT, false);
        _generateL2Json(SCROLL, RESTRICTED_LIMIT, false);
        _generateL2Json(SWELL, RESTRICTED_LIMIT, false);
        _generateL2Json(STABLE, RESTRICTED_LIMIT, false);
    }

    function _setupPeers() internal {
        // Group 1 — Restricted: 20 weETH / 4h
        allL2Eids.push(BLAST.L2_EID);   allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(MODE.L2_EID);    allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(MORPH.L2_EID);   allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(ZKSYNC.L2_EID);  allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(SONIC.L2_EID);   allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(SCROLL.L2_EID);  allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(STABLE.L2_EID);  allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(AVAX.L2_EID);    allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(SWELL.L2_EID);   allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(BNB.L2_EID);     allL2Limits.push(RESTRICTED_LIMIT);
        allL2Eids.push(BERA.L2_EID);    allL2Limits.push(RESTRICTED_LIMIT);

        // Group 2 — Standard: 2,000 weETH / 4h
        allL2Eids.push(LINEA.L2_EID);     allL2Limits.push(STANDARD_LIMIT);
        allL2Eids.push(UNICHAIN.L2_EID);  allL2Limits.push(STANDARD_LIMIT);
        allL2Eids.push(HYPEREVM.L2_EID);  allL2Limits.push(STANDARD_LIMIT);
        allL2Eids.push(PLASMA.L2_EID);    allL2Limits.push(STANDARD_LIMIT);
        allL2Eids.push(INK.L2_EID);       allL2Limits.push(STANDARD_LIMIT);
        allL2Eids.push(MONAD.L2_EID);     allL2Limits.push(STANDARD_LIMIT);

        // Group 3 — High-throughput
        allL2Eids.push(BASE.L2_EID);  allL2Limits.push(BASE_LIMIT);
        allL2Eids.push(OP.L2_EID);    allL2Limits.push(OP_LIMIT);
    }

    function _generateEthereumJson() internal {
        string memory json = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);

        // Tx 1: Unpause
        string memory unpauseHex = iToHex(abi.encodeWithSignature("unpauseBridge()"));
        json = string.concat(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), unpauseHex, false));

        // Tx 2-3: Rate limits (per-peer, matching each L2's group rate)
        PairwiseRateLimiter.RateLimitConfig[] memory rlConfig = new PairwiseRateLimiter.RateLimitConfig[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            rlConfig[i] = LayerZeroHelpers._getRateLimitConfig(allL2Eids[i], allL2Limits[i], RATE_WINDOW);
        }
        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rlConfig));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rlConfig));
        json = string.concat(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), outboundData, false));
        json = string.concat(json, _getGnosisTransaction(addressToHex(L1_OFT_ADAPTER), inboundData, false));

        // Tx 4-5: DVN config (4 required DVNs for all L2 peers)
        bytes memory ulnBytes = _encode4DVNUlnConfig(L1_DVN);
        SetConfigParam[] memory dvnParams = new SetConfigParam[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            dvnParams[i] = SetConfigParam(allL2Eids[i], 2, ulnBytes);
        }
        string memory sendCfg = iToHex(abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])", L1_OFT_ADAPTER, L1_SEND_302, dvnParams
        ));
        string memory recvCfg = iToHex(abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])", L1_OFT_ADAPTER, L1_RECEIVE_302, dvnParams
        ));
        json = string.concat(json, _getGnosisTransaction(addressToHex(L1_ENDPOINT), sendCfg, false));
        json = string.concat(json, _getGnosisTransaction(addressToHex(L1_ENDPOINT), recvCfg, true));

        vm.writeJson(json, "./output/ethereum-SecurityUpgrade.json");
    }

    function _generateL2Json(ConfigPerL2 storage chain, uint256 chainLimit, bool shouldUnpause) internal {
        string memory json = _getGnosisHeader(chain.CHAIN_ID, chain.L2_CONTRACT_CONTROLLER_SAFE);

        // Tx 1: Unpause (conditional)
        if (shouldUnpause) {
            string memory unpauseHex = iToHex(abi.encodeWithSignature("unpauseBridge()"));
            json = string.concat(json, _getGnosisTransaction(addressToHex(chain.L2_OFT), unpauseHex, false));
        }

        // Tx 2-3: Rate limits (all peers get this chain's group rate)
        PairwiseRateLimiter.RateLimitConfig[] memory rlConfig = new PairwiseRateLimiter.RateLimitConfig[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            if (allL2Eids[i] == chain.L2_EID) {
                rlConfig[i] = LayerZeroHelpers._getRateLimitConfig(L1_EID, chainLimit, RATE_WINDOW);
            } else {
                rlConfig[i] = LayerZeroHelpers._getRateLimitConfig(allL2Eids[i], chainLimit, RATE_WINDOW);
            }
        }
        string memory outboundData = iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rlConfig));
        string memory inboundData = iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rlConfig));
        json = string.concat(json, _getGnosisTransaction(addressToHex(chain.L2_OFT), outboundData, false));
        json = string.concat(json, _getGnosisTransaction(addressToHex(chain.L2_OFT), inboundData, false));

        // Tx 4-5: DVN config (4 required DVNs for all peers)
        bytes memory ulnBytes = _encode4DVNUlnConfig(chain.LZ_DVN);
        SetConfigParam[] memory dvnParams = new SetConfigParam[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            if (allL2Eids[i] == chain.L2_EID) {
                dvnParams[i] = SetConfigParam(L1_EID, 2, ulnBytes);
            } else {
                dvnParams[i] = SetConfigParam(allL2Eids[i], 2, ulnBytes);
            }
        }
        string memory sendCfg = iToHex(abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])", chain.L2_OFT, chain.SEND_302, dvnParams
        ));
        string memory recvCfg = iToHex(abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])", chain.L2_OFT, chain.RECEIVE_302, dvnParams
        ));
        json = string.concat(json, _getGnosisTransaction(addressToHex(chain.L2_ENDPOINT), sendCfg, false));
        json = string.concat(json, _getGnosisTransaction(addressToHex(chain.L2_ENDPOINT), recvCfg, true));

        vm.writeJson(json, string.concat("./output/", chain.NAME, "-SecurityUpgrade.json"));
    }

    function _encode4DVNUlnConfig(address[4] memory dvns) internal pure returns (bytes memory) {
        address[] memory requiredDVNs = new address[](4);
        requiredDVNs[0] = dvns[0];
        requiredDVNs[1] = dvns[1];
        requiredDVNs[2] = dvns[2];
        requiredDVNs[3] = dvns[3];

        // Bubble sort ascending (LZ endpoint requires sorted DVN array)
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3 - i; j++) {
                if (requiredDVNs[j] > requiredDVNs[j + 1]) {
                    (requiredDVNs[j], requiredDVNs[j + 1]) = (requiredDVNs[j + 1], requiredDVNs[j]);
                }
            }
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 4,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        return abi.encode(ulnConfig);
    }
}
