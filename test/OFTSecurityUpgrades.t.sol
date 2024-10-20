// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../utils/Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";
import "../contracts/PairwiseRateLimiter.sol";
import "../contracts/EtherfiOFTAdapterUpgradeable.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// a test suite for the security features we are adding to the OFT contracts {pausing, rate limiting}
contract TestOFTSecurityUpgrades is Test, Constants, LayerZeroHelpers, GnosisHelpers {
    ConfigPerL2 public TEST_L2;
    address public pauser;
    address public unpauser;
    EtherfiOFTUpgradeable public oft;
    EtherfiOFTAdapterUpgradeable public oftAdapter;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    enum Status {
        Success,
        PauseRevert,
        InboundRateLimitRevert,
        OutboundRateLimitRevert
    }

    function setUpMainnet() public {
        TEST_L2 = BASE;
        pauser = PAUSER_EOA;
        unpauser = L1_CONTRACT_CONTROLLER;
        oftAdapter = EtherfiOFTAdapterUpgradeable(L1_OFT_ADAPTER);
        vm.createSelectFork(L1_RPC_URL);

        executeGnosisTransactionBundle("./output/schedule-oft-adapter-upgrade.json", L1_TIMELOCK_GNOSIS);
        vm.warp(block.timestamp + 259200 + 1);
        executeGnosisTransactionBundle("./output/execute-oft-adapter-upgrade.json", L1_TIMELOCK_GNOSIS);
        executeGnosisTransactionBundle("./output/configure-mainnet-security.json", L1_CONTRACT_CONTROLLER);
    }

    function setUpL2() public {
        TEST_L2 = BASE;
        pauser = PAUSER_EOA;
        unpauser = TEST_L2.L2_CONTRACT_CONTROLLER_SAFE;
        oft = EtherfiOFTUpgradeable(TEST_L2.L2_OFT);
        vm.createSelectFork(TEST_L2.RPC_URL);

        executeGnosisTransactionBundle("./output/security-upgrade-base.json", TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
    }

    function test_onlyOwnerAccessControl() public {
        setUpL2();

        address defaultAdmin = vm.addr(3);

        // making owner and default admin different addresses
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        oft.renounceRole(DEFAULT_ADMIN_ROLE, TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        vm.stopPrank();

        // ensure that default admin can't do things
        vm.startPrank(defaultAdmin);

        PairwiseRateLimiter.RateLimitConfig[] memory rateLimitConfigArray = new PairwiseRateLimiter.RateLimitConfig[](1);
        rateLimitConfigArray[0] = PairwiseRateLimiter.RateLimitConfig({
            peerEid: L1_EID,
            limit: STANDBY_LIMIT,
            window: STANDBY_WINDOW
        });
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oft.setInboundRateLimits(rateLimitConfigArray);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oft.setOutboundRateLimits(rateLimitConfigArray);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oft.grantRole(MINTER_ROLE, pauser);

        // ensure the owner can do things
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);

        oft.setInboundRateLimits(rateLimitConfigArray);
        oft.setOutboundRateLimits(rateLimitConfigArray);
        oft.grantRole(MINTER_ROLE, pauser);
        oft.revokeRole(MINTER_ROLE, pauser);
        vm.stopPrank();
        
        setUpMainnet();

        // making the owner and default admin different addresses
        vm.startPrank(L1_CONTRACT_CONTROLLER);
        oftAdapter.grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        oftAdapter.renounceRole(DEFAULT_ADMIN_ROLE, L1_CONTRACT_CONTROLLER);
        vm.stopPrank();

        // ensure that default admin can't do things
        vm.startPrank(defaultAdmin);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oftAdapter.setInboundRateLimits(rateLimitConfigArray);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oftAdapter.setOutboundRateLimits(rateLimitConfigArray);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, defaultAdmin));
        oftAdapter.grantRole(UNPAUSER_ROLE, pauser);

        // ensure the owner can do things
        vm.startPrank(L1_CONTRACT_CONTROLLER);

        oftAdapter.setInboundRateLimits(rateLimitConfigArray);
        oftAdapter.setOutboundRateLimits(rateLimitConfigArray);
        oftAdapter.grantRole(UNPAUSER_ROLE, pauser);
        oftAdapter.revokeRole(UNPAUSER_ROLE, pauser);

        vm.stopPrank();
    }

    function test_pauseAccessControl() public {
        setUpL2();

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, TEST_L2.L2_CONTRACT_CONTROLLER_SAFE, PAUSER_ROLE));
        oft.pauseBridge();

        vm.prank(pauser);
        oft.pauseBridge();

        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauser, UNPAUSER_ROLE));
        oft.unpauseBridge();

        vm.prank(unpauser);
        oft.unpauseBridge();

        setUpMainnet();

        vm.prank(L1_CONTRACT_CONTROLLER);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, L1_CONTRACT_CONTROLLER, PAUSER_ROLE));
        oftAdapter.pauseBridge();

        vm.prank(pauser);
        oftAdapter.pauseBridge();

        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauser, UNPAUSER_ROLE));
        oftAdapter.unpauseBridge();

        vm.prank(unpauser);
        oftAdapter.unpauseBridge();
    }

    // testing the pausing functionality of the OFT token against cross chain transfers
    function test_pauseOFT() public {
        setUpL2();

        // simulate outbound cross chain transfers
        _sendCrossChain(1 ether, Status.Success);

        vm.prank(pauser);
        oft.pauseBridge();

        _sendCrossChain(1 ether, Status.PauseRevert);

        vm.prank(unpauser);
        oft.unpauseBridge();

        _sendCrossChain(1 ether, Status.Success);

        // simulate inbound cross chain transfers
        _mockCrossChainReceive(1 ether, Status.Success);

        vm.prank(pauser);
        oft.pauseBridge();

        _mockCrossChainReceive(1 ether, Status.PauseRevert);

        vm.prank(unpauser);
        oft.unpauseBridge();

        _mockCrossChainReceive(1 ether, Status.Success);
    }

    // testing the pausing functionality of the OFT adapter against cross chain transfers
    function test_pauseOFTAdapter() public {
        setUpMainnet();

        // simulate outbound cross chain transfers
        _sendCrossChain(1 ether, Status.Success);

        vm.prank(pauser);
        oftAdapter.pauseBridge();

        _sendCrossChain(1 ether, Status.PauseRevert);

        vm.prank(unpauser);
        oftAdapter.unpauseBridge();

        _sendCrossChain(1 ether, Status.Success);

        // simulate inbound cross chain transfers
        _mockCrossChainReceive(1 ether, Status.Success);

        vm.prank(pauser);
        oftAdapter.pauseBridge();

        _mockCrossChainReceive(1 ether, Status.PauseRevert);

        vm.prank(unpauser);
        oftAdapter.unpauseBridge();

        _mockCrossChainReceive(1 ether, Status.Success);
    }

    function test_rateLimitOFT() public {
        setUpL2();

        (uint256 outboundAmountInFlight, uint256 amountCanBeSent) = oft.getAmountCanBeSent(L1_EID);
        _sendCrossChain(10 ether, Status.Success);
        (uint256 outboundAmountInFlightAfter, uint256 amountCanBeSentAfter) = oft.getAmountCanBeSent(L1_EID);

        assertEq(outboundAmountInFlight + 10 ether, outboundAmountInFlightAfter);
        assertEq(amountCanBeSent - 10 ether, amountCanBeSentAfter);

        _mockCrossChainReceive(2 ether, Status.Success);
        (uint256 inboundAmountInFlight, uint256 amountCanBeReceived) = oft.getAmountCanBeReceived(L1_EID);

        assertEq(inboundAmountInFlight, 2 ether);
        assertEq(amountCanBeReceived, 1998 ether);

        _sendCrossChain(1995 ether, Status.OutboundRateLimitRevert);
        _mockCrossChainReceive(1995 ether, Status.Success);
        _mockCrossChainReceive(5 ether, Status.InboundRateLimitRevert);

        // warp forward 4 hours
        vm.warp(block.timestamp + 14400);

        _sendCrossChain(1995 ether, Status.Success);
        _mockCrossChainReceive(1995 ether, Status.Success);
    }

    function test_rateLimitOFTAdapter() public {
        setUpMainnet();

        _sendCrossChain(10 ether, Status.Success);
        (uint256 outboundAmountInFlightAfter, uint256 amountCanBeSentAfter) = oftAdapter.getAmountCanBeSent(TEST_L2.L2_EID);

        assertEq(10 ether, outboundAmountInFlightAfter);
        assertEq(1990 ether, amountCanBeSentAfter);

        _mockCrossChainReceive(2 ether, Status.Success);
        (uint256 inboundAmountInFlight, uint256 amountCanBeReceived) = oftAdapter.getAmountCanBeReceived(TEST_L2.L2_EID);

        assertEq(inboundAmountInFlight, 2 ether);
        assertEq(amountCanBeReceived, 1998 ether);

        _sendCrossChain(1995 ether, Status.OutboundRateLimitRevert);
        _mockCrossChainReceive(1995 ether, Status.Success);
        _mockCrossChainReceive(5 ether, Status.InboundRateLimitRevert);

        // warp forward 4 hours
        vm.warp(block.timestamp + 14400);

        _sendCrossChain(1995 ether, Status.Success);
        _mockCrossChainReceive(1995 ether, Status.Success);
    }

    // mock an inbound cross chain transfer
    function _mockCrossChainReceive(uint256 amount, Status status) internal {
        // setting params based on our current chain
        address peerAddress = L1_OFT_ADAPTER;
        address lzEndpoint = TEST_L2.L2_ENDPOINT;
        uint32 srcEid = L1_EID;
        if (block.chainid == 1) {
            peerAddress = TEST_L2.L2_OFT;
            lzEndpoint = L1_ENDPOINT;
            srcEid = TEST_L2.L2_EID;
        }

        address receiver = vm.addr(1);

        // Construct mock inbound transfer message from L1
        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: _toBytes32(peerAddress),
            nonce: 1
        });
        bytes32 _guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        bytes32 _sendTo = _toBytes32(receiver);
        
        // converting the amount to be received to LZs 6 decimal standand
        uint64 _amountShared =  uint64(amount / 10e11);
        bytes memory _message = abi.encodePacked(_sendTo, _amountShared);

        vm.prank(lzEndpoint);
        if (status == Status.PauseRevert) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        } else if (status == Status.OutboundRateLimitRevert) {
            vm.expectRevert(PairwiseRateLimiter.OutboundRateLimitExceeded.selector);
        } else if (status == Status.InboundRateLimitRevert) {
            vm.expectRevert(PairwiseRateLimiter.InboundRateLimitExceeded.selector);
        }
        if (block.chainid == 1) {
            oftAdapter.lzReceive(origin, _guid, _message, address(0), "");
        } else {
            oft.lzReceive(origin, _guid, _message, address(0), "");
        }
    }

    // helper function to simulate outbound cross chain transfers 
    function _sendCrossChain(uint256 amount, Status status) internal {
        address sender = vm.addr(1);

        // configuring based on our current chain
        address weETH = address(oft);
        address localOFTContract = address(oft);
        uint32 dstEid = L1_EID;
        if (block.chainid == 1) {
            weETH = L1_WEETH;
            localOFTContract = L1_OFT_ADAPTER;
            dstEid = TEST_L2.L2_EID;
        }

        vm.deal(sender, amount);
        deal(address(weETH), address(sender), amount);

        vm.prank(sender);
        IERC20(weETH).approve(localOFTContract, amount);
        SendParam memory param = SendParam({
            dstEid: dstEid,
            to: _toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });

        IOFT oftInterface = IOFT(localOFTContract);
        MessagingFee memory fee = oftInterface.quoteSend(param, false);

        if (status == Status.PauseRevert) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        } else if (status == Status.OutboundRateLimitRevert) {
            vm.expectRevert(PairwiseRateLimiter.OutboundRateLimitExceeded.selector);
        } else if (status == Status.InboundRateLimitRevert) {
            vm.expectRevert(PairwiseRateLimiter.InboundRateLimitExceeded.selector);
        }
        vm.prank(sender);
        oftInterface.send{value: fee.nativeFee}(
            param,
            fee,
            sender
        );
    }
}

