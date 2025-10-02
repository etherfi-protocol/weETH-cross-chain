// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../contracts/native-minting/l2-syncpools/L2OPStackSyncPoolETHUpgradeable.sol";
import "../contracts/native-minting/layerzero-base/L2BaseSyncPoolUpgradeable.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";

contract GenerateLineaNativeMintingDeprecation is Script, Test, L2Constants, GnosisHelpers {
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function run() public {
        _generateTransactionBundle();
        _testTransactionsOnFork();
    }

    function _generateTransactionBundle() internal {
        bytes memory revokeRoleData = abi.encodeWithSignature(
            "revokeRole(bytes32,address)", 
            MINTER_ROLE, 
            LINEA.L2_SYNC_POOL
        );
        
        bytes memory setMinSyncData = abi.encodeWithSignature(
            "setMinSyncAmount(address,uint256)", 
            ETH_ADDRESS, 
            0
        );
        
        string memory transactionJson = _getGnosisHeader(LINEA.CHAIN_ID, LINEA.L2_CONTRACT_CONTROLLER_SAFE);
        
        transactionJson = string.concat(
            transactionJson, 
            _getGnosisTransaction(
                addressToHex(LINEA.L2_OFT), 
                iToHex(revokeRoleData), 
                false
            )
        );
        
        transactionJson = string.concat(
            transactionJson, 
            _getGnosisTransaction(
                addressToHex(LINEA.L2_SYNC_POOL), 
                iToHex(setMinSyncData), 
                true
            )
        );
        
        vm.writeJson(transactionJson, "./output/linea-native-minting-deprecation-bundle.json");
    }

    function _testTransactionsOnFork() internal {
        vm.createSelectFork(LINEA.RPC_URL);
        
        executeGnosisTransactionBundle("./output/linea-native-minting-deprecation-bundle.json", LINEA.L2_CONTRACT_CONTROLLER_SAFE);
        
        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(LINEA.L2_OFT);
        L2OPStackSyncPoolETHUpgradeable syncPool = L2OPStackSyncPoolETHUpgradeable(LINEA.L2_SYNC_POOL);
        
        bool hasMinterRoleAfter = oft.hasRole(MINTER_ROLE, LINEA.L2_SYNC_POOL);
        assertFalse(hasMinterRoleAfter, "MINTER_ROLE should be revoked");
        
        L2BaseSyncPoolUpgradeable.Token memory tokenData = syncPool.getTokenData(ETH_ADDRESS);
        assertEq(tokenData.minSyncAmount, 0, "Min sync amount should be set to 0 for ETH");
    }
}
