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
import "forge-std/Test.sol";
import "forge-std/console.sol";

/**
 * @title Native Minting Unit Tests
 * @notice Test suite for verifying native minting functionality across L1 and L2
 */
contract NativeMintingUnitTests is Test, L2Constants, GnosisHelpers {
    // Events for verifying bridge messages
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message
    );

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

    /// @notice Test native minting functionality and deposit/sync on L2
    function testNativeMintingL2() public {
        // Setup L2 environment
        vm.createSelectFork(BERA.RPC_URL);
        L2NativeMintingScript nativeMintingL2 = new L2NativeMintingScript();
        // contracts have already been deployed hence no need to simulate deployments
        // nativeMintingL2.run();
        vm.stopPrank();
 
        executeGnosisTransactionBundle("./output/setBeraMinter.json", BERA.L2_CONTRACT_CONTROLLER_SAFE);
        vm.warp(block.timestamp + 3600);

        // Test deposit functionality
        HydraSyncPoolETHUpgradeable syncPool = HydraSyncPoolETHUpgradeable(BERA.L2_SYNC_POOL);
        address user = vm.addr(2);
        deal(HYDRA_WETH, user, 1 ether);
        startHoax(user);
        IERC20(HYDRA_WETH).approve(address(syncPool), 1 ether);
        syncPool.deposit(HYDRA_WETH, MESSAGE_VALUE, 0.90 ether);

        assertApproxEqAbs(IERC20(BERA.L2_OFT).balanceOf(user), 0.95 ether, 0.01 ether);
        assertEq(IERC20(HYDRA_WETH).balanceOf(address(syncPool)), 1 ether);

        // Test sync functionality
        (MessagingFee memory standardFee, uint256 totalFee) = syncPool.quoteSyncTotal(HYDRA_WETH, hex"", false);
        
        syncPool.sync{value: totalFee}(HYDRA_WETH, hex"", standardFee);
    }

    /// @notice Test upgrade to native minting functionality and fast/slow sync on L1
    function testNativeMintingL1() public {
        // Setup L1 environment
        vm.createSelectFork(L1_RPC_URL);
        L1NativeMintingScript nativeMintingL1 = new L1NativeMintingScript();
        // contracts have already been deployed hence no need to simulate deployments
        // nativeMintingL1.run();
        vm.stopPrank();

        // Execute timelock transactions
        executeGnosisTransactionBundle("./output/L1NativeMintingScheduleTransactions.json", L1_TIMELOCK_GNOSIS);
        vm.warp(block.timestamp + 259200 + 1); // Advance past timelock period
        executeGnosisTransactionBundle("./output/L1NativeMintingExecuteTransactions.json", L1_TIMELOCK_GNOSIS);
        executeGnosisTransactionBundle("./output/L1NativeMintingSetConfig.json", L1_CONTRACT_CONTROLLER);

        // Test fast-sync scenario
        EtherfiL1SyncPoolETH L1syncPool = EtherfiL1SyncPoolETH(L1_SYNC_POOL);
        uint256 lockBoxBalanceBefore = IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());

        // Mock inbound LayerZero message from L2SyncPool
        // used the data from this call:
        // https://testnet.layerzeroscan.com/tx/0x8e5c7921fb807656aaa435a4cd675ff265cb51941035cb8d9f5008880f8e134e
        Origin memory origin = Origin({
            srcEid: BERA.L2_EID,
            sender:LayerZeroHelpers._toBytes32(BERA.L2_SYNC_POOL),
            nonce: 1
        });
        bytes32 guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        address lzExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
        bytes memory messageL2Message = hex"000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000001630dfdb2353000000000000000000000000000000000000000000000000000015181ff25a98000";
        uint256 expectedEthAmountReceived = 99939000000000000;
        uint256 expectedWeEthAmountReceived = IWeEth(L1_WEETH).getWeETHByeETH(expectedEthAmountReceived);

        vm.prank(L1_ENDPOINT);  
        L1syncPool.lzReceive(origin, guid, messageL2Message, lzExecutor, "");
        
        // verify the amount of beraDummyToken minted
        IERC20 beraDummyToken = IERC20(BERA.L1_DUMMY_TOKEN);
        assertEq(beraDummyToken.balanceOf(L1_VAMP), expectedEthAmountReceived);

        // verify the amount of weETH sent to the lockbox
        uint256 lockBoxBalanceAfter = IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());
        assertEq(lockBoxBalanceAfter - lockBoxBalanceBefore, expectedWeEthAmountReceived);

        // Test slow-sync scenario
        uint256 vampBalanceBefore = L1_VAMP.balance;
        L1HydraReceiverETHUpgradeable receiver = L1HydraReceiverETHUpgradeable(payable(BERA.L1_RECEIVER));

        vm.deal(BERA.L1_MESSENGER, expectedEthAmountReceived);

        EtherfiL1SyncPoolETH l1SyncPool = EtherfiL1SyncPoolETH(L1_SYNC_POOL);
        address receiverAddress = l1SyncPool.getReceiver(BERA.L2_EID);

        vm.prank(BERA.L1_MESSENGER);
        receiver.lzCompose{value: expectedEthAmountReceived}(
            STARGATE_POOL_NATIVE, 
            0xed142b220cff2ca95267ee1e3c50b526290e113002d2010d625ce03ce1a5e7fb, 
            hex"00000000000000090000769a00000000000000000000000000000000000000000000000001630dfdb235300000000000000000000000000097a81e9ae7051243912e6acff860c92c9b12657d000000000000000000000000000000000000000000000000015181ff25a98000", 
            lzExecutor, 
            "");

        assertEq(vampBalanceBefore + expectedEthAmountReceived, L1_VAMP.balance);
    }
}
