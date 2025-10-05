// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../contracts/native-minting/l2-syncpools/HydraSyncPoolETHUpgradeable.sol";
import "../contracts/native-minting/layerzero-base/L2BaseSyncPoolUpgradeable.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";

contract GenerateBeraNativeMintingDeprecation is Script, Test, L2Constants, GnosisHelpers {
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address constant HYDRA_WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    function run() public {
        _generateTransactionBundle();
        _testTransactionsOnFork();
    }

    function _generateTransactionBundle() internal {
        bytes memory revokeRoleData = abi.encodeWithSignature(
            "revokeRole(bytes32,address)", 
            MINTER_ROLE, 
            BERA.L2_SYNC_POOL
        );
        
        bytes memory setMinSyncData = abi.encodeWithSignature(
            "setMinSyncAmount(address,uint256)", 
            HYDRA_WETH, 
            0
        );
        
        string memory transactionJson = _getGnosisHeader(BERA.CHAIN_ID, BERA.L2_CONTRACT_CONTROLLER_SAFE);
        
        transactionJson = string.concat(
            transactionJson, 
            _getGnosisTransaction(
                addressToHex(BERA.L2_OFT), 
                iToHex(revokeRoleData), 
                false
            )
        );
        
        transactionJson = string.concat(
            transactionJson, 
            _getGnosisTransaction(
                addressToHex(BERA.L2_SYNC_POOL), 
                iToHex(setMinSyncData), 
                true
            )
        );
        
        vm.writeJson(transactionJson, "./output/bera-native-minting-deprecation-bundle.json");
    }

    function _testTransactionsOnFork() internal {
        vm.createSelectFork(BERA.RPC_URL);
        
        executeGnosisTransactionBundle("./output/bera-native-minting-deprecation-bundle.json", BERA.L2_CONTRACT_CONTROLLER_SAFE);
        
        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(BERA.L2_OFT);
        HydraSyncPoolETHUpgradeable syncPool = HydraSyncPoolETHUpgradeable(BERA.L2_SYNC_POOL);
        
        bool hasMinterRoleAfter = oft.hasRole(MINTER_ROLE, BERA.L2_SYNC_POOL);
        assertFalse(hasMinterRoleAfter, "MINTER_ROLE should be revoked");
        
        L2BaseSyncPoolUpgradeable.Token memory tokenData = syncPool.getTokenData(HYDRA_WETH);
        assertEq(tokenData.minSyncAmount, 0, "Min sync amount should be set to 0 for WETH");
    }
}
