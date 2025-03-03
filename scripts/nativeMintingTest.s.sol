// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../scripts/native-minting-deployment/DeployConfigureL1.s.sol";
import "../scripts/native-minting-deployment/DeployConfigureL2.s.sol";
import "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../contracts/native-minting/l2-syncpools/HydraSyncPoolETHUpgradeable.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "../contracts/native-minting/BucketRateLimiter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IScrollMessenger.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/AppendOnlyMerkleTree.sol";
import "../interfaces/IWeEth.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title Native Minting Script
 * @notice Script for executing native minting functionality across L1 and L2
 */
contract NativeMintingScript is Script, L2Constants, GnosisHelpers {
    //  Canonical bridge message expected values
    address private SENDER = BERA.L2_SYNC_POOL;
    address private TARGET = BERA.L1_RECEIVER;
    uint256 private MESSAGE_VALUE = 1 ether;
    bytes private BRIDGE_MESSAGE = hex"3a69197e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000007606ebd50bcf19f47f644e6981a58d2287a3b8d6c0702ffa0a1cb9ecdd12c568a498000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000d2ddfc66b17a973";
    
    // addition constants for hydra deployment
    // hydra deployed wETH on bera
    address constant HYDRA_WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // StargateOFTETH deployed on bera
    address constant STARGATE_OFT_ETH = 0x45f1A95A4D3f3836523F5c83673c797f4d4d263B;
    
    // StargatePoolNative deployed on mainnet
    address constant STARGATE_POOL_NATIVE = 0x77b2043768d28E9C9aB44E1aBfC95944bcE57931;

    /// @notice Execute native minting functionality and deposit/sync on L2
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Setup L2 environment
        vm.startBroadcast(deployerPrivateKey);

        // Test deposit functionality
        HydraSyncPoolETHUpgradeable syncPool = HydraSyncPoolETHUpgradeable(BERA.L2_SYNC_POOL);
        
        IERC20(HYDRA_WETH).approve(address(syncPool), 2230300000000000);
        syncPool.deposit(HYDRA_WETH, 2230300000000000, 1230300000000000);

        // assertApproxEqAbs(IERC20(BERA.L2_OFT).balanceOf(user), 0.95 ether, 0.01 ether);
        // assertEq(IERC20(HYDRA_WETH).balanceOf(address(syncPool)), 1 ether);

        // // Test sync functionality
        // (MessagingFee memory standardFee, uint256 totalFee) = syncPool.quoteSyncTotal(HYDRA_WETH, hex"", false);
        
        // syncPool.sync{value: totalFee}(HYDRA_WETH, hex"", standardFee);
    }
}
