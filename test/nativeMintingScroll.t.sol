// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../scripts/NativeMintingDeployment/DeployConfigureL1.s.sol";
import "../scripts/NativeMintingDeployment/DeployConfigureL2.s.sol";
import "../contracts/NativeMinting/EtherfiL1SyncPoolETH.sol";
import "../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "../contracts/NativeMinting/BucketRateLimiter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IScrollMessenger.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../libraries/AppendOnlyMerkleTree.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

/**
 * @title Native Minting Unit Tests
 * @notice Test suite for verifying native minting functionality across L1 and L2
 */
contract NativeMintingUnitTests is Test, L2Constants, GnosisHelpers, LayerZeroHelpers {
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
    address private SENDER = SCROLL.L2_SYNC_POOL;
    address private TARGET = SCROLL.L1_RECEIVER;
    uint256 private MESSAGE_VALUE = 1 ether;
    bytes private BRIDGE_MESSAGE = hex"3a69197e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000009ceadcb40313553905cf94c7eb16af232cadaf0846110869647d43d85c96428c228c000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000d32e708032b6efe";

    /// @notice Test the upgrade to natvie minting functionalilty and deposit/sync on L2
    function testNativeMintingL2() public {
        // Setup L2 environment
        vm.createSelectFork(SCROLL.RPC_URL);
        L2NativeMintingScript nativeMintingL2 = new L2NativeMintingScript();
        nativeMintingL2.run();
 
        executeGnosisTransactionBundle("./output/setScrollMinter.json", SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        vm.warp(block.timestamp + 3600);

        // Test deposit functionality
        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(SCROLL.L2_SYNC_POOL);
        address user = vm.addr(2);
        startHoax(user);
        syncPool.deposit{value: 1 ether}(Constants.ETH_ADDRESS, MESSAGE_VALUE, 0.95 ether);

        assertApproxEqAbs(IERC20(SCROLL.L2_OFT).balanceOf(user), 0.95 ether, 0.01 ether);
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
            BRIDGE_MESSAGE
        );
        
        syncPool.sync{value: msgFee.nativeFee}(Constants.ETH_ADDRESS, hex"", msgFee);
    }

    /// @notice Test upgrade to native minting functionality and fast/slow sync on L1
    function testNativeMintingL1() public {
        // Setup L1 environment
        // vm.createSelectFork(L1_RPC_URL);
        // L1NativeMintingScript nativeMintingL1 = new L1NativeMintingScript();
        // nativeMintingL1.run();

        // // Execute timelock transactions
        // executeGnosisTransactionBundle("./output/L1NativeMintingScheduleTransactions.json", L1_TIMELOCK_GNOSIS);
        // vm.warp(block.timestamp + 2); // Advance past timelock period
        // executeGnosisTransactionBundle("./output/L1NativeMintingExecuteTransactions.json", L1_TIMELOCK_GNOSIS);

        // address delegate = ILayerZeroEndpointV2(L1_ENDPOINT).delegates(L1_SYNC_POOL);
        // console.log(delegate);
        // executeGnosisTransactionBundle("./output/L1NativeMintingSetConfig.json", L1_CONTRACT_CONTROLLER);

        // Test fast-sync scenario
        vm.createSelectFork(L1_RPC_URL);
        EtherfiL1SyncPoolETH L1syncPool = EtherfiL1SyncPoolETH(L1_SYNC_POOL);
        uint256 lockBoxBalanceBefore = IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());

        // Mock inbound LayerZero message from L2SyncPool
        // used the data from this call:
        // https://layerzeroscan.com/tx/0x1107ae898ad34e942d2e007dbb358c26d24ec578d8e9628fafa9b6c1727ae92d
        Origin memory origin = Origin({
            srcEid: SCROLL.L2_EID,
            sender: _toBytes32(SCROLL.L2_SYNC_POOL),
            nonce: 1
        });
        bytes32 guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        address lzExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
        bytes memory messageL2Message = hex"000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000429d069189e000000000000000000000000000000000000000000000000000003f5abb59a8d07b2";
        
        vm.prank(L1_ENDPOINT);
        L1syncPool.lzReceive(origin, guid, messageL2Message, lzExecutor, "");

        // Verify fast-sync results
        // IERC20 scrollDummyToken = IERC20(SCROLL.L1_DUMMY_TOKEN);
        // assertApproxEqAbs(scrollDummyToken.balanceOf(L1_VAMP), 334.114 ether, 0.01 ether);
        // uint256 lockBoxBalanceAfter = IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());
        // // As eETH continues to appreciate, the amount received from this fast-sync will decrease from the original 317 weETH
        // assertApproxEqAbs(lockBoxBalanceAfter, lockBoxBalanceBefore + 317 ether, 1 ether);

        // Test slow-sync scenario
        uint256 vampBalanceBefore = L1_VAMP.balance;

        // // Mock Scroll messenger call
        // vm.store(
        //     address(0x50c7d3e7f7c656493D1D76aaa1a836CedfCBB16A),
        //     bytes32(0x00000000000000000000000000000000000000000000000000000000000000c9),
        //     bytes32(uint256(uint160(SENDER)))
        // );

        // startHoax(0x50c7d3e7f7c656493D1D76aaa1a836CedfCBB16A);
        // (bool success, ) = TARGET.call{value: MESSAGE_VALUE}(BRIDGE_MESSAGE);
        // require(success, "Message call failed");

        // assertEq(vampBalanceBefore + MESSAGE_VALUE, L1_VAMP.balance);
    }

}
