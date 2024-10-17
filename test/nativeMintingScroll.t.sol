// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../scripts/NativeMintingDeployment/02_DeployConfigureL1.s.sol";
import "../scripts/NativeMintingDeployment/01_DeployConfigureL2.s.sol";
import "../scripts/NativeMintingDeployment/03_ConfigureL2.s.sol";
import "../contracts/NativeMinting/EtherfiL1SyncPoolETH.sol";
import "../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "../contracts/NativeMinting/BucketRateLimiter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IScrollMessenger.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../libraries/AppendOnlyMerkleTree.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract nativeMintingUnitTests is Test, L2Constants, GnosisHelpers, LayerZeroHelpers {
    

    // event and data emitted from the scroll bridge
    // useful to verify withdrawal message emitted from L2 bridge == message executed on mainnet
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message
    );
    address constant sender = 0x6D411e0A54382eD43F02410Ce1c7a7c122afA6E1;
    address constant target = 0x5d47653d3921731EaB6d9BA4805208dD55cfaDd0;
    uint256 constant value = 1 ether;
    bytes constant message = hex"3a69197e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000076061dcd5c213ae94098d843cce51b89ea93fe77df630c2b3ed2d4929d520b44e986000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000d344af4eb17b1e7";

    function testNativeMintingL1() public {
        vm.createSelectFork(L1_RPC_URL);

        L1NativeMintingScript nativeMintingL1 = new L1NativeMintingScript();
        nativeMintingL1.run();
        console.log("L1 Receiver: ", l1Receiver);

        executeGnosisTransactionBundle("./output/L1NativeMintingScheduleTransactions.json", L1_TIMELOCK_GNOSIS);
        
        // warp block to the timelock execution
        vm.warp(block.timestamp + 259200 + 1);

        executeGnosisTransactionBundle("./output/L1NativeMintingExecuteTransactions.json", L1_TIMELOCK_GNOSIS);
        executeGnosisTransactionBundle("./output/L1NativeMintingSetConfig.json", L1_CONTRACT_CONTROLLER);

        // mock a `fast-sync` 
        EtherfiL1SyncPoolETH L1syncPool = EtherfiL1SyncPoolETH(L1_SYNC_POOL);

        // get lockbox balance before
        uint256 lockBoxBalanceBefore =  IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());

        // Construct mock inbound LZ message from L2SyncPool
        Origin memory origin = Origin({
            srcEid: SCROLL.L2_EID,
            sender: _toBytes32(nativeMintingL1.L2_SYNC_POOL()),
            nonce: 1
        });
        bytes32 guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        address lzExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
        bytes memory messageL2Message = hex"000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000008bf92a3188ea37b2c600000000000000000000000000000000000000000000008539e6cb6ac88d1154";
        vm.prank(L1_ENDPOINT);
        L1syncPool.lzReceive(origin, guid, messageL2Message, lzExecutor, "");

        IERC20 scrollDummyToken = IERC20(nativeMintingL1.dummyToken());

        assertApproxEqAbs(scrollDummyToken.balanceOf(L1_VAMP), 2582 ether, 1 ether);

        // get lockbox balance after
        uint256 lockBoxBalanceAfter =  IERC20(L1_WEETH).balanceOf(L1syncPool.getLockBox());
        assertApproxEqAbs(lockBoxBalanceAfter, lockBoxBalanceBefore + 2457 ether, 1 ether);

        // mock a `slow-sync`

        uint256 vampBalanceBefore = L1_VAMP.balance; 

        // line of code called in `L1ScrollMessenger.relayMessageWithProof` called after verification of the proof
        address _to = target;
        uint256 _value = value;
        bytes memory _message = message;

        vm.store(
            address(0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367),
            bytes32(0x00000000000000000000000000000000000000000000000000000000000000c9),
            bytes32(uint256(uint160(sender)))
        );

        // prank from the message proxy
        vm.prank(0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367);
        
        (bool success, ) = _to.call{value: _value}(_message);

        assertEq(vampBalanceBefore + 1 ether, L1_VAMP.balance);
    }

    address constant l1Receiver = 0x5d47653d3921731EaB6d9BA4805208dD55cfaDd0; 

    function testNativeMintingL2() public {
        vm.createSelectFork(SCROLL.RPC_URL);

        L2NativeMintingScript nativeMintingL2 = new L2NativeMintingScript();
        address l2SyncPool = nativeMintingL2.run();
 
        L2ConfigureNativeMinting configureNativeMinting = new L2ConfigureNativeMinting();
        configureNativeMinting.run(l2SyncPool, l1Receiver);

        executeGnosisTransactionBundle("./output/setMinter.json", SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(l2SyncPool);
        vm.warp(block.timestamp + 3600);

        // simulation a deposit
        address user = vm.addr(2);
        startHoax(user);
        syncPool.deposit{value: 1 ether}(Constants.ETH_ADDRESS, 1 ether, 0.95 ether);

        assertApproxEqAbs(IERC20(SCROLL.L2_OFT).balanceOf(user), 0.95 ether, 0.01 ether);
        assertEq(address(syncPool).balance, 1 ether);

        // simulation a sync call
        MessagingFee memory msgFee = syncPool.quoteSync(Constants.ETH_ADDRESS, hex"", false);

        
        // get the expected message nonce
        uint256 messageNonce = AppendOnlyMerkleTree(0x5300000000000000000000000000000000000000).nextMessageIndex();

        vm.expectEmit(true, true, false, true); // (checkTopic1, checkTopic2, checkTopic3, checkData)
        emit SentMessage(
            sender,
            target,
            value,
            messageNonce,
            0,
            message
        );
        syncPool.sync{value: msgFee.nativeFee}(Constants.ETH_ADDRESS, hex"", msgFee);
    }

}
