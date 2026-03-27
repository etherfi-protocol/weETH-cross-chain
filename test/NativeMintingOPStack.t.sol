// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../contracts/native-minting/l2-syncpools/L2OPStackSyncPoolETHUpgradeable.sol";
import "../contracts/native-minting/layerzero-base/L2BaseSyncPoolUpgradeable.sol";
import "../contracts/native-minting/receivers/L1ScrollReceiverETHUpgradeable.sol";
import "../contracts/native-minting/DummyTokenUpgradeable.sol";
import "../contracts/libraries/Constants.sol";
import "../interfaces/IWeEth.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";

contract NativeMintingOPStackForkTest is Test, L2Constants, GnosisHelpers {

    // ================================================================
    //                    L2: Deposit and Sync
    // ================================================================

    function testOPStackL2DepositAndSync() public {
        vm.createSelectFork(OP.RPC_URL);

        // Execute the generated gnosis config transactions on the deployed contracts
        executeGnosisTransactionBundle("./output/op_L2_GrantMinter.json", OP.L2_CONTRACT_CONTROLLER_SAFE);
        executeGnosisTransactionBundle("./output/op_L2_SetMinSync.json", OP.L2_CONTRACT_CONTROLLER_SAFE);

        // Let the bucket rate limiter refill after fresh deployment
        vm.warp(block.timestamp + 1 hours);

        L2OPStackSyncPoolETHUpgradeable syncPool = L2OPStackSyncPoolETHUpgradeable(payable(OP.L2_SYNC_POOL));

        address user = address(0xBEEF);
        uint256 depositAmount = 0.1 ether;
        vm.deal(user, 10 ether);

        // --- Reject non-ETH deposits ---
        address fakeToken = address(0xdead);
        vm.prank(user);
        vm.expectRevert(L2BaseSyncPoolUpgradeable.L2BaseSyncPool__UnauthorizedToken.selector);
        syncPool.deposit(fakeToken, depositAmount, 0);

        // --- Reject amountIn / msg.value mismatch ---
        vm.prank(user);
        vm.expectRevert(L2BaseSyncPoolUpgradeable.L2BaseSyncPool__InvalidAmountIn.selector);
        syncPool.deposit{value: 0.01 ether}(Constants.ETH_ADDRESS, depositAmount, 0);

        // --- Deposit ETH ---
        vm.startPrank(user);
        uint256 amountOut = syncPool.deposit{value: depositAmount}(Constants.ETH_ADDRESS, depositAmount, 0);
        vm.stopPrank();

        console.log("Deposit amount:", depositAmount);
        console.log("weETH received:", amountOut);

        assertGt(amountOut, 0, "No weETH minted");
        assertEq(IERC20(OP.L2_OFT).balanceOf(user), amountOut, "User weETH balance mismatch");
        assertEq(address(syncPool).balance, depositAmount, "SyncPool should hold deposited ETH");

        // --- Sync to L1 (sends LZ fast message + OP bridge slow message) ---
        vm.startPrank(user);
        MessagingFee memory fee = syncPool.quoteSync(Constants.ETH_ADDRESS, "", false);
        console.log("Sync LZ fee:", fee.nativeFee);

        (uint256 unsyncedIn, uint256 unsyncedOut) = syncPool.sync{value: fee.nativeFee}(
            Constants.ETH_ADDRESS, "", fee
        );
        vm.stopPrank();

        console.log("Synced amountIn:", unsyncedIn);
        console.log("Synced amountOut:", unsyncedOut);

        assertEq(unsyncedIn, depositAmount, "Synced amountIn should match deposit");
        assertEq(unsyncedOut, amountOut, "Synced amountOut should match minted");
        assertEq(address(syncPool).balance, 0, "SyncPool should be empty after sync");
    }

    // ================================================================
    //       L1: Fast Path (LZ) + Slow Path (Bridge Receiver)
    // ================================================================

    function testOPStackL1InboundSync() public {
        vm.createSelectFork(L1_RPC_URL);

        // Execute the generated gnosis timelock + controller config transactions
        executeGnosisTransactionBundle("./output/op_L1_TimelockSchedule.json", L1_TIMELOCK_GNOSIS);
        vm.warp(block.timestamp + 3 days);
        executeGnosisTransactionBundle("./output/op_L1_TimelockExecute.json", L1_TIMELOCK_GNOSIS);
        executeGnosisTransactionBundle("./output/op_L1_ControllerConfig.json", L1_CONTRACT_CONTROLLER);

        EtherfiL1SyncPoolETH l1SyncPool = EtherfiL1SyncPoolETH(L1_SYNC_POOL);
        DummyTokenUpgradeable dummyToken = DummyTokenUpgradeable(OP.L1_DUMMY_TOKEN);

        uint256 amountIn = 1 ether;
        uint256 amountOut = IWeEth(L1_WEETH).getWeETHByeETH(amountIn);

        _testFastPath(l1SyncPool, dummyToken, amountIn, amountOut);
        _testSlowPath(l1SyncPool, dummyToken, amountIn, amountOut);
    }

    // ================================================================
    //                    Fast Path: LZ lzReceive
    // ================================================================

    function _testFastPath(
        EtherfiL1SyncPoolETH l1SyncPool,
        DummyTokenUpgradeable dummyToken,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        address lockBox = l1SyncPool.getLockBox();
        uint256 lockBoxWeETHBefore = IERC20(L1_WEETH).balanceOf(lockBox);

        Origin memory origin = Origin({
            srcEid: OP.L2_EID,
            sender: LayerZeroHelpers._toBytes32(OP.L2_SYNC_POOL),
            nonce: 1
        });
        bytes memory lzMessage = abi.encode(Constants.ETH_ADDRESS, amountIn, amountOut);

        vm.prank(L1_ENDPOINT);
        l1SyncPool.lzReceive(origin, keccak256("op-fast-sync"), lzMessage, address(0), "");

        assertEq(
            dummyToken.balanceOf(l1SyncPool.getLiquifier()),
            amountIn,
            "Dummy tokens should be deposited in liquifier"
        );

        uint256 lockBoxWeETHAfter = IERC20(L1_WEETH).balanceOf(lockBox);
        assertGt(lockBoxWeETHAfter, lockBoxWeETHBefore, "Lockbox should have more weETH after fast path");
        console.log("Fast path - weETH to lockbox:", lockBoxWeETHAfter - lockBoxWeETHBefore);
    }

    // ================================================================
    //             Slow Path: OP Bridge via L1 Receiver
    // ================================================================

    function _testSlowPath(
        EtherfiL1SyncPoolETH l1SyncPool,
        DummyTokenUpgradeable dummyToken,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        L1ScrollReceiverETHUpgradeable receiver = L1ScrollReceiverETHUpgradeable(OP.L1_RECEIVER);
        uint256 dummySupplyBefore = dummyToken.totalSupply();

        bytes memory bridgeMessage = abi.encode(
            OP.L2_EID, keccak256("op-slow-sync"), Constants.ETH_ADDRESS, amountIn, amountOut
        );

        // Mock the OP L1 CrossDomainMessenger's xDomainMessageSender to return the L2 sync pool
        vm.mockCall(
            OP.L1_MESSENGER,
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(OP.L2_SYNC_POOL)
        );

        vm.deal(OP.L1_MESSENGER, amountIn);
        vm.prank(OP.L1_MESSENGER);
        receiver.onMessageReceived{value: amountIn}(bridgeMessage);

        uint256 dummySupplyAfter = dummyToken.totalSupply();
        assertLt(dummySupplyAfter, dummySupplyBefore, "Dummy token supply should decrease after slow path");
        console.log("Slow path - dummy tokens burned:", dummySupplyBefore - dummySupplyAfter);

        assertEq(
            dummyToken.balanceOf(l1SyncPool.getLiquifier()),
            0,
            "Liquifier dummy balance should be zero after slow path"
        );
    }
}
