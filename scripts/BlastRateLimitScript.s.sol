// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/PairwiseRateLimiter.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";
import "../contracts/native-minting/l2-syncpools/L2OPStackSyncPoolETHUpgradeable.sol";
import "../contracts/native-minting/layerzero-base/L2BaseSyncPoolUpgradeable.sol";
import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";

interface IGnosisSafe {
    function nonce() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function approveHash(bytes32 hashToApprove) external;
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}

contract BlastRateLimitScript is Test, L2Constants {
    using LayerZeroHelpers for *;
    
    uint256 constant RESTRICTED_LIMIT = 50 ether;
    uint256 constant RESTRICTED_WINDOW = 12 hours;
    address constant MULTI_SEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;

    function run() public {
        vm.createSelectFork("https://rpc.blast.io");
        
        ConfigPerL2 memory blastConfig = BLAST;
        IGnosisSafe safe = IGnosisSafe(blastConfig.L2_CONTRACT_CONTROLLER_SAFE);
        uint256 nonce = safe.nonce();
        
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

        bytes memory multiSendData = _createAllTransactionData(blastConfig, outboundConfig, inboundConfig);
        
        bytes32 txHash = _getTransactionHash(
            safe,
            MULTI_SEND_ADDRESS,
            multiSendData,
            nonce
        );

        console.log("Transaction Hash:", vm.toString(txHash));
        
        _approveHashWithSigners(safe, txHash);
        
        _executeTransaction(safe, MULTI_SEND_ADDRESS, multiSendData);
        
        _verifyRateLimitsUpdated(blastConfig.L2_OFT, outboundConfig, inboundConfig);
        _verifySyncPoolUpdates(blastConfig.L2_OFT, blastConfig.L2_SYNC_POOL);
    }

    function _getTransactionHash(
        IGnosisSafe safe,
        address multiSendAddress,
        bytes memory multiSendData,
        uint256 nonce
    ) internal view returns (bytes32) {
        return safe.getTransactionHash(multiSendAddress, 0, multiSendData, 1, 0, 0, 0, address(0), address(0), nonce);
    }
    
    function _createAllTransactionData(
        ConfigPerL2 memory blastConfig,
        PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig,
        PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig
    ) internal pure returns (bytes memory) {
        bytes memory setOutboundData = abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", outboundConfig);
        bytes memory setInboundData = abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", inboundConfig);
        
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        bytes memory revokeMinterData = abi.encodeWithSignature("revokeRole(bytes32,address)", MINTER_ROLE, blastConfig.L2_SYNC_POOL);
        bytes memory setMinSyncData = abi.encodeWithSignature("setMinSyncAmount(address,uint256)", ETH_ADDRESS, 0);
        
        return _createMultiSendData(
            blastConfig.L2_OFT, setOutboundData,
            blastConfig.L2_OFT, setInboundData,
            blastConfig.L2_OFT, revokeMinterData,
            blastConfig.L2_SYNC_POOL, setMinSyncData
        );
    }
    
    function _createMultiSendData(
        address target1,
        bytes memory data1,
        address target2,
        bytes memory data2,
        address target3,
        bytes memory data3,
        address target4,
        bytes memory data4
    ) internal pure returns (bytes memory) {
        bytes memory transaction1 = abi.encodePacked(
            uint8(0), 
            target1,
            uint256(0), 
            uint256(data1.length),
            data1
        );
        
        bytes memory transaction2 = abi.encodePacked(
            uint8(0), 
            target2,
            uint256(0), 
            uint256(data2.length),
            data2
        );
        
        bytes memory transaction3 = abi.encodePacked(
            uint8(0), 
            target3,
            uint256(0), 
            uint256(data3.length),
            data3
        );
        
        bytes memory transaction4 = abi.encodePacked(
            uint8(0), 
            target4,
            uint256(0), 
            uint256(data4.length),
            data4
        );

        return abi.encodeWithSignature("multiSend(bytes)", abi.encodePacked(transaction1, transaction2, transaction3, transaction4));
    }
    
    function _approveHashWithSigners(IGnosisSafe safe, bytes32 txHash) internal {
        address[] memory owners = safe.getOwners();
        uint256 threshold = safe.getThreshold();
        
        console.log("Approving hash with signers...");
        console.log("Required threshold:", threshold);
        console.log("Total owners:", owners.length);
        
        // Approve hash with each owner (up to threshold)
        for (uint256 i = 0; i < threshold && i < owners.length; i++) {
            address owner = owners[i];
            console.log("Approving hash with owner:", owner);
            
            // Use vm.prank to mock the owner calling approveHash
            vm.prank(owner);
            safe.approveHash(txHash);
        }
    }
    
    function _executeTransaction(IGnosisSafe safe, address to, bytes memory data) internal {
        console.log("Executing transaction...");
        
        address[] memory owners = safe.getOwners();
        uint256 threshold = safe.getThreshold();
        // Create signatures for approved hashes first
        bytes memory signatures = _createApprovedHashSignatures(owners, threshold);
        
        // Use the first signer as executor (after sorting)
        address executor = _getFirstSignerFromSignatures(signatures);
        
        console.log("Executing with owner:", executor);
        
        // Use vm.prank to mock the owner executing the transaction
        vm.prank(executor);
        
        bool success = safe.execTransaction(
            to,           // to
            0,            // value
            data,         // data
            1,            // operation (DelegateCall)
            0,            // safeTxGas
            0,            // baseGas
            0,            // gasPrice
            address(0),   // gasToken
            payable(0),   // refundReceiver
            signatures    // signatures
        );
        
        require(success, "Transaction execution failed");
        console.log("Transaction executed successfully");
    }
    
    function _createApprovedHashSignatures(address[] memory owners, uint256 threshold) internal pure returns (bytes memory) {
        bytes memory signatures = new bytes(threshold * 65);
        
        address[] memory sortedOwners = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            sortedOwners[i] = owners[i];
        }
        
        for (uint256 i = 0; i < threshold - 1; i++) {
            for (uint256 j = 0; j < threshold - i - 1; j++) {
                if (sortedOwners[j] > sortedOwners[j + 1]) {
                    address temp = sortedOwners[j];
                    sortedOwners[j] = sortedOwners[j + 1];
                    sortedOwners[j + 1] = temp;
                }
            }
        }
        
        for (uint256 i = 0; i < threshold; i++) {
            uint256 offset = i * 65;
            
            bytes32 r = bytes32(uint256(uint160(sortedOwners[i])));
            bytes32 s = bytes32(0);
            uint8 v = 1;
            
            assembly {
                mstore(add(signatures, add(32, offset)), r)
                mstore(add(signatures, add(64, offset)), s)
                mstore8(add(signatures, add(96, offset)), v)
            }
        }
        
        return signatures;
    }
    
    function _getFirstSignerFromSignatures(bytes memory signatures) internal pure returns (address) {
        bytes32 r;
        assembly {
            r := mload(add(signatures, 32))
        }
        return address(uint160(uint256(r)));
    }
    
    function _verifyRateLimitsUpdated(
        address oftAddress, 
        PairwiseRateLimiter.RateLimitConfig[] memory outboundConfig,
        PairwiseRateLimiter.RateLimitConfig[] memory inboundConfig
    ) internal {
        console.log("Verifying rate limits were updated...");
        
        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(oftAddress);
        
        for (uint256 i = 0; i < outboundConfig.length; i++) {
            (,,uint256 limit, uint256 window) = oft.outboundRateLimits(outboundConfig[i].peerEid);
            
            assertEq(limit, outboundConfig[i].limit, "Outbound rate limit not updated correctly");
            assertEq(window, outboundConfig[i].window, "Outbound rate limit window not updated correctly");

            console.log("Outbound rate limit for peerEid", outboundConfig[i].peerEid);
            console.log("limit", limit);
            console.log("window", window);
        }
        
        for (uint256 i = 0; i < inboundConfig.length; i++) {
            (,,uint256 limit, uint256 window) = oft.inboundRateLimits(inboundConfig[i].peerEid);
            
            assertEq(limit, inboundConfig[i].limit, "Inbound rate limit not updated correctly");
            assertEq(window, inboundConfig[i].window, "Inbound rate limit window not updated correctly");

            console.log("Inbound rate limit for peerEid", inboundConfig[i].peerEid);
            console.log("limit", limit);
            console.log("window", window);
        }
        
        console.log("All rate limits verified successfully!");
    }
    
    function _verifySyncPoolUpdates(address oftAddress, address syncPoolAddress) internal {
        console.log("Verifying sync pool updates...");
        
        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(oftAddress);
        L2OPStackSyncPoolETHUpgradeable syncPool = L2OPStackSyncPoolETHUpgradeable(syncPoolAddress);
        
        // Verify minter role was revoked
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        bool hasMinterRole = oft.hasRole(MINTER_ROLE, syncPoolAddress);
        
        console.log("Sync pool has minter role:", hasMinterRole);
        assertFalse(hasMinterRole, "Minter role should be revoked from sync pool");
        
        // Verify min sync amount was set to 0 for ETH
        L2BaseSyncPoolUpgradeable.Token memory tokenData = syncPool.getTokenData(ETH_ADDRESS);
        
        console.log("Min sync amount verification:");
        console.log("ETH address:", ETH_ADDRESS);
        console.log("Min sync amount:", tokenData.minSyncAmount);
        
        assertEq(tokenData.minSyncAmount, 0, "Min sync amount should be set to 0 for ETH");
        
        console.log("All sync pool updates verified successfully!");
    }
}
