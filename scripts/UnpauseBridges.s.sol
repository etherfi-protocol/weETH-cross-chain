// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

contract UnpauseBridges is Script, L2Constants, GnosisHelpers {

    function run() public {
        bytes memory unpauseData = abi.encodeWithSignature("unpauseBridge()");
        string memory unpauseDataHex = iToHex(unpauseData);

        // Ethereum (L1 OFT Adapter)
        _writeUnpauseJson("1", L1_CONTRACT_CONTROLLER, L1_OFT_ADAPTER, unpauseDataHex, "ethereum");

        // L2 OFTs
        _writeUnpauseJson(BASE.CHAIN_ID, BASE.L2_CONTRACT_CONTROLLER_SAFE, BASE.L2_OFT, unpauseDataHex, "base");
        _writeUnpauseJson(OP.CHAIN_ID, OP.L2_CONTRACT_CONTROLLER_SAFE, OP.L2_OFT, unpauseDataHex, "op");
        _writeUnpauseJson(UNICHAIN.CHAIN_ID, UNICHAIN.L2_CONTRACT_CONTROLLER_SAFE, UNICHAIN.L2_OFT, unpauseDataHex, "unichain");
        _writeUnpauseJson(MONAD.CHAIN_ID, MONAD.L2_CONTRACT_CONTROLLER_SAFE, MONAD.L2_OFT, unpauseDataHex, "monad");
        _writeUnpauseJson(LINEA.CHAIN_ID, LINEA.L2_CONTRACT_CONTROLLER_SAFE, LINEA.L2_OFT, unpauseDataHex, "linea");
        _writeUnpauseJson(SWELL.CHAIN_ID, SWELL.L2_CONTRACT_CONTROLLER_SAFE, SWELL.L2_OFT, unpauseDataHex, "swell");
        _writeUnpauseJson(BERA.CHAIN_ID, BERA.L2_CONTRACT_CONTROLLER_SAFE, BERA.L2_OFT, unpauseDataHex, "bera");
        _writeUnpauseJson(AVAX.CHAIN_ID, AVAX.L2_CONTRACT_CONTROLLER_SAFE, AVAX.L2_OFT, unpauseDataHex, "avax");
        _writeUnpauseJson(INK.CHAIN_ID, INK.L2_CONTRACT_CONTROLLER_SAFE, INK.L2_OFT, unpauseDataHex, "ink");
        _writeUnpauseJson(BNB.CHAIN_ID, BNB.L2_CONTRACT_CONTROLLER_SAFE, BNB.L2_OFT, unpauseDataHex, "bnb");
        _writeUnpauseJson(ZKSYNC.CHAIN_ID, ZKSYNC.L2_CONTRACT_CONTROLLER_SAFE, ZKSYNC.L2_OFT, unpauseDataHex, "zksync");
        _writeUnpauseJson(SONIC.CHAIN_ID, SONIC.L2_CONTRACT_CONTROLLER_SAFE, SONIC.L2_OFT, unpauseDataHex, "sonic");
        _writeUnpauseJson(PLASMA.CHAIN_ID, PLASMA.L2_CONTRACT_CONTROLLER_SAFE, PLASMA.L2_OFT, unpauseDataHex, "plasma");
        _writeUnpauseJson(HYPEREVM.CHAIN_ID, HYPEREVM.L2_CONTRACT_CONTROLLER_SAFE, HYPEREVM.L2_OFT, unpauseDataHex, "hyperevm");
    }

    function _writeUnpauseJson(
        string memory chainId,
        address safe,
        address oft,
        string memory data,
        string memory name
    ) internal {
        string memory json = _getGnosisHeader(chainId, safe);
        json = string.concat(json, _getGnosisTransaction(addressToHex(oft), data, true));
        vm.writeJson(json, string.concat("./output/", name, "-unpauseBridge.json"));
    }
}
