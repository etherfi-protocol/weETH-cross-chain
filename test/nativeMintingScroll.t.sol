// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../scripts/native-minting-deployment/DeployConfigureL1.s.sol";
import "../scripts/native-minting-deployment/DeployConfigureL2.s.sol";
import "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../contracts/native-minting/l2-syncpools/L2ScrollSyncPoolETHUpgradeable.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "../contracts/native-minting/BucketRateLimiter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IScrollMessenger.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../utils/AppendOnlyMerkleTree.sol";

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

    /// @notice Test the upgrade to natvie minting functionalilty and deposit/sync on L2
    function testNativeMintingL2() public {
        // Setup L2 environment
        vm.createSelectFork(BERA.RPC_URL);
        L2NativeMintingScript nativeMintingL2 = new L2NativeMintingScript();
        // contracts have already been deployed hence no need to simulate deployments
        nativeMintingL2.run();
        vm.stopPrank();
 
        executeGnosisTransactionBundle("./output/setBeraMinter.json", BERA.L2_CONTRACT_CONTROLLER_SAFE);
        vm.warp(block.timestamp + 3600);

        // Test deposit functionality
        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(BERA.L2_SYNC_POOL);
        address user = vm.addr(2);
        startHoax(user);
        syncPool.deposit{value: 1 ether}(Constants.ETH_ADDRESS, MESSAGE_VALUE, 0.90 ether);

        assertApproxEqAbs(IERC20(BERA.L2_OFT).balanceOf(user), 0.95 ether, 0.01 ether);
        assertEq(address(syncPool).balance, 1 ether);

        // Test sync functionality
        MessagingFee memory msgFee = syncPool.quoteSync(Constants.ETH_ADDRESS, hex"", false);
        uint256 messageNonce = AppendOnlyMerkleTree(0x5300000000000000000000000000000000000000).nextMessageIndex();

        vm.expectEmit(true, true, false, true);
        emit SentMessage(
            SENDER,
            TARGET,
            MESSAGE_VALUE,
            messageNonce,
            0,
            // this value becomes inaccurate as the oracle price changes
            BRIDGE_MESSAGE
        );
        
        syncPool.sync{value: msgFee.nativeFee}(Constants.ETH_ADDRESS, hex"", msgFee);
    }

    /// @notice Test upgrade to native minting functionality and fast/slow sync on L1
    function testNativeMintingL1() public {
        // Setup L1 environment
        vm.createSelectFork(L1_RPC_URL);
        L1NativeMintingScript nativeMintingL1 = new L1NativeMintingScript();
        // contracts have already been deployed hence no need to simulate deployments
        nativeMintingL1.run();
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
        // https://layerzeroscan.com/tx/0x1107ae898ad34e942d2e007dbb358c26d24ec578d8e9628fafa9b6c1727ae92d
        Origin memory origin = Origin({
            srcEid: BERA.L2_EID,
            sender:LayerZeroHelpers._toBytes32(BERA.L2_SYNC_POOL),
            nonce: 1
        });
        bytes32 guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        address lzExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
        bytes memory messageL2Message = hex"000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000b3391361c5231ab1400000000000000000000000000000000000000000000000a923986bbf6435c87";
        
        vm.prank(L1_ENDPOINT);
        L1syncPool.lzReceive(origin, guid, messageL2Message, lzExecutor, "");

        // Verify fast-sync results
        IERC20 beraDummyToken = IERC20(BERA.L1_DUMMY_TOKEN);
        assertApproxEqAbs(beraDummyToken.balanceOf(L1_VAMP), 206.63 ether, 0.01 ether);
        uint256 lockBoxBalanceAfter = IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());
        assertApproxEqAbs(lockBoxBalanceAfter, lockBoxBalanceBefore + 194 ether, 1 ether);

        // Test slow-sync scenario
        uint256 vampBalanceBefore = L1_VAMP.balance;

        // Mock Scroll messenger call
        vm.store(
            address(0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367),
            bytes32(0x00000000000000000000000000000000000000000000000000000000000000c9),
            bytes32(uint256(uint160(SENDER)))
        );

        vm.prank(0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367);
        (bool success, ) = TARGET.call{value: MESSAGE_VALUE}(BRIDGE_MESSAGE);
        require(success, "Message call failed");

        assertEq(vampBalanceBefore + MESSAGE_VALUE, L1_VAMP.balance);
    }

}
