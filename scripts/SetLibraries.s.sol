// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

/// @notice Generates Gnosis Safe JSON transactions that pin the send/receive libraries
///         for the weETH OFT on all 20 chains. This removes reliance on the LayerZero
///         default library, preventing the Endpoint owner from swapping it.
contract SetLibraries is Script, L2Constants, GnosisHelpers {

    uint32[] allL2Eids;

    function run() public {
        _setupPeers();

        _generateEthereumJson();

        _generateL2Json(BASE);
        _generateL2Json(OP);
        _generateL2Json(UNICHAIN);
        _generateL2Json(LINEA);
        _generateL2Json(BERA);
        _generateL2Json(AVAX);
        _generateL2Json(BNB);
        _generateL2Json(ZKSYNC);
        _generateL2Json(SONIC);
        _generateL2Json(HYPEREVM);
        _generateL2Json(SCROLL);
        _generateL2Json(BLAST);
        _generateL2Json(MODE);
        _generateL2Json(MORPH);
        _generateL2Json(SWELL);
        _generateL2Json(MONAD);
        _generateL2Json(PLASMA);
        _generateL2Json(INK);
        _generateL2Json(STABLE);
    }

    function _setupPeers() internal {
        allL2Eids.push(BLAST.L2_EID);
        allL2Eids.push(MODE.L2_EID);
        allL2Eids.push(MORPH.L2_EID);
        allL2Eids.push(ZKSYNC.L2_EID);
        allL2Eids.push(SONIC.L2_EID);
        allL2Eids.push(SCROLL.L2_EID);
        allL2Eids.push(STABLE.L2_EID);
        allL2Eids.push(AVAX.L2_EID);
        allL2Eids.push(SWELL.L2_EID);
        allL2Eids.push(BNB.L2_EID);
        allL2Eids.push(BERA.L2_EID);
        allL2Eids.push(LINEA.L2_EID);
        allL2Eids.push(UNICHAIN.L2_EID);
        allL2Eids.push(HYPEREVM.L2_EID);
        allL2Eids.push(PLASMA.L2_EID);
        allL2Eids.push(INK.L2_EID);
        allL2Eids.push(MONAD.L2_EID);
        allL2Eids.push(BASE.L2_EID);
        allL2Eids.push(OP.L2_EID);
    }

    function _generateEthereumJson() internal {
        string memory json = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);
        string memory endpointHex = addressToHex(L1_ENDPOINT);

        for (uint256 i = 0; i < allL2Eids.length; i++) {
            string memory data = iToHex(abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)", L1_OFT_ADAPTER, allL2Eids[i], L1_SEND_302
            ));
            json = string.concat(json, _getGnosisTransaction(endpointHex, data, false));
        }

        for (uint256 i = 0; i < allL2Eids.length; i++) {
            bool isLast = (i == allL2Eids.length - 1);
            string memory data = iToHex(abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)", L1_OFT_ADAPTER, allL2Eids[i], L1_RECEIVE_302, 0
            ));
            json = string.concat(json, _getGnosisTransaction(endpointHex, data, isLast));
        }

        vm.writeJson(json, "./output/ethereum-SetLibraries.json");
    }

    function _generateL2Json(ConfigPerL2 storage chain) internal {
        string memory json = _getGnosisHeader(chain.CHAIN_ID, chain.L2_CONTRACT_CONTROLLER_SAFE);
        string memory endpointHex = addressToHex(chain.L2_ENDPOINT);

        for (uint256 i = 0; i < allL2Eids.length; i++) {
            uint32 peerEid = allL2Eids[i] == chain.L2_EID ? L1_EID : allL2Eids[i];
            string memory data = iToHex(abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)", chain.L2_OFT, peerEid, chain.SEND_302
            ));
            json = string.concat(json, _getGnosisTransaction(endpointHex, data, false));
        }

        for (uint256 i = 0; i < allL2Eids.length; i++) {
            uint32 peerEid = allL2Eids[i] == chain.L2_EID ? L1_EID : allL2Eids[i];
            bool isLast = (i == allL2Eids.length - 1);
            string memory data = iToHex(abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)", chain.L2_OFT, peerEid, chain.RECEIVE_302, 0
            ));
            json = string.concat(json, _getGnosisTransaction(endpointHex, data, isLast));
        }

        vm.writeJson(json, string.concat("./output/", chain.NAME, "-SetLibraries.json"));
    }
}
