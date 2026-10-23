// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ICreditRedirect} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/ICreditRedirect.sol";
import {SendParam, OFTReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";

import {EtherfiOFTAdapterUpgradeable} from "../contracts/EtherFiOFTAdapterUpgradeable.sol";
import {OFTControls} from "../contracts/OFTControls.sol";
import {PairwiseRateLimiter} from "../contracts/PairwiseRateLimiter.sol";
import {PausableUntil} from "../contracts/PausableUntil.sol";
import {OFTEndpointMock} from "./mock/OFTEndpointMock.sol";

contract TestWeETH is ERC20 {
    constructor() ERC20("Wrapped eETH", "weETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OFTControlsAdapterTest is Test {
    uint32 constant PEER_EID = 30184;
    uint256 constant LIMIT = 1_000_000 ether;
    uint256 constant WINDOW = 1 days;

    OFTEndpointMock endpoint;
    TestWeETH weETH;
    EtherfiOFTAdapterUpgradeable adapter;

    address owner = makeAddr("owner");
    address pauser = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address guardian = makeAddr("guardian");
    address blacklister = makeAddr("blacklister");
    address rateManager = makeAddr("rateManager");
    address feeDeposit = makeAddr("feeDeposit");
    address escrow = makeAddr("escrow");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    bytes32 peer = bytes32(uint256(uint160(makeAddr("peer"))));

    function setUp() public {
        vm.warp(1_800_000_000);
        endpoint = new OFTEndpointMock(30101);
        weETH = new TestWeETH();
        EtherfiOFTAdapterUpgradeable impl = new EtherfiOFTAdapterUpgradeable(address(weETH), address(endpoint));
        adapter = EtherfiOFTAdapterUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (owner, owner))
        )));

        PairwiseRateLimiter.RateLimitConfig[] memory limits = new PairwiseRateLimiter.RateLimitConfig[](1);
        limits[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, LIMIT, WINDOW);

        vm.startPrank(owner);
        adapter.initializeControls(feeDeposit, 1 days);
        adapter.setPeer(PEER_EID, peer);
        adapter.setOutboundRateLimits(limits);
        adapter.setInboundRateLimits(limits);
        adapter.grantRole(adapter.PAUSER_ROLE(), pauser);
        adapter.grantRole(adapter.UNPAUSER_ROLE(), unpauser);
        adapter.grantRole(adapter.PAUSER_UNTIL_ROLE(), guardian);
        adapter.grantRole(adapter.BLACKLISTER_ROLE(), blacklister);
        adapter.grantRole(adapter.RATE_LIMIT_MANAGER_ROLE(), rateManager);
        vm.stopPrank();

        weETH.mint(user, 1000 ether);
        weETH.mint(address(adapter), 500 ether); // already locked from earlier sends
    }

    function _send(address from, uint256 amount, uint256 minAmount) internal returns (OFTReceipt memory receipt) {
        SendParam memory param = SendParam(PEER_EID, bytes32(uint256(uint160(from))), amount, minAmount, "", "", "");
        MessagingFee memory fee = adapter.quoteSend(param, false);
        vm.deal(from, 1 ether);
        vm.prank(from);
        weETH.approve(address(adapter), amount);
        vm.prank(from);
        (, receipt) = adapter.send{value: fee.nativeFee}(param, fee, from);
    }

    function sendExternal(address from, uint256 amount) external {
        _send(from, amount, 0);
    }

    function _receive(address to, uint256 amountLD) internal {
        Origin memory origin = Origin(PEER_EID, peer, 1);
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(to))), uint64(amountLD / 1e12));
        vm.prank(address(endpoint));
        adapter.lzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function receiveExternal(address to, uint256 amount) external {
        _receive(to, amount);
    }

    function _enableBlacklistMode() internal {
        vm.startPrank(owner);
        adapter.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(address(adapter), escrow));
        adapter.setAllowlistMode(OFTControls.AllowlistMode.Blacklist);
        vm.stopPrank();
    }

    function _blacklist(address account) internal {
        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](1);
        params[0] = OFTControls.SetAllowlistParam(account, true);
        vm.prank(blacklister);
        adapter.setBlacklisted(params);
    }

    function test_Defaults_LockAndUnlock() public {
        OFTReceipt memory receipt = _send(user, 100 ether, 100 ether);
        assertEq(receipt.amountReceivedLD, 100 ether);
        assertEq(weETH.balanceOf(address(adapter)), 600 ether);

        _receive(user2, 40 ether);
        assertEq(weETH.balanceOf(user2), 40 ether);
        assertEq(weETH.balanceOf(address(adapter)), 560 ether);
    }

    function test_Fee_StaysLockedMinusFee() public {
        vm.prank(owner);
        adapter.setDefaultFeeBps(50);

        OFTReceipt memory receipt = _send(user, 100 ether, 99 ether);
        assertEq(receipt.amountReceivedLD, 99.5 ether);
        assertEq(weETH.balanceOf(feeDeposit), 0.5 ether);
        // what stays locked matches what the destination mints
        assertEq(weETH.balanceOf(address(adapter)), 500 ether + 99.5 ether);
    }

    function test_Fee_SlippageProtectionTrips() public {
        vm.prank(owner);
        adapter.setDefaultFeeBps(50);
        vm.expectRevert();
        adapter.quoteSend(SendParam(PEER_EID, bytes32(uint256(1)), 100 ether, 100 ether, "", "", ""), false);
    }

    function test_Blacklist_SenderCannotBridge() public {
        _enableBlacklistMode();
        _blacklist(user);
        vm.expectRevert();
        this.sendExternal(user, 1 ether);
    }

    function test_CreditRedirect_BlockedRecipientGetsEscrow() public {
        _enableBlacklistMode();
        _blacklist(user2);
        _receive(user2, 25 ether);
        assertEq(weETH.balanceOf(user2), 0);
        assertEq(weETH.balanceOf(escrow), 25 ether);
    }

    function test_Roles_UseAccessControl() public {
        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](1);
        params[0] = OFTControls.SetAllowlistParam(user, true);
        bytes32 role = adapter.BLACKLISTER_ROLE();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
        adapter.setBlacklisted(params);
    }

    function test_PauseUntil_StopsBridgeThenExpires() public {
        vm.prank(guardian);
        adapter.pauseBridgeUntil();
        uint256 until = adapter.pausedUntil();

        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        this.sendExternal(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        this.receiveExternal(user2, 1 ether);

        vm.warp(until + 1);
        _send(user, 1 ether, 1 ether);
    }

    function test_PauseUntil_GuardianCannotUseIndefinitePause() public {
        bytes32 role = adapter.PAUSER_ROLE();
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, role));
        adapter.pauseBridge();
    }

    function test_GlobalPause_StillWorks() public {
        vm.prank(pauser);
        adapter.pauseBridge();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        this.sendExternal(user, 1 ether);
        vm.prank(unpauser);
        adapter.unpauseBridge();
        _send(user, 1 ether, 1 ether);
    }

    function test_LanePause_BlocksOnlyThatLane() public {
        uint32[] memory eids = new uint32[](1);
        eids[0] = PEER_EID;
        vm.prank(pauser);
        adapter.pauseLanes(eids);

        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.sendExternal(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.receiveExternal(user2, 1 ether);

        vm.prank(unpauser);
        adapter.unpauseLanes(eids);
        _send(user, 1 ether, 1 ether);
    }

    function test_Tighten_ManagerCanLowerButNotRaise() public {
        PairwiseRateLimiter.RateLimitConfig[] memory lower = new PairwiseRateLimiter.RateLimitConfig[](1);
        lower[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, LIMIT / 2, WINDOW);
        PairwiseRateLimiter.RateLimitConfig[] memory higher = new PairwiseRateLimiter.RateLimitConfig[](1);
        higher[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, LIMIT * 2, WINDOW);

        vm.startPrank(rateManager);
        adapter.tightenRateLimits(lower, true);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.RateLimitNotTightening.selector, PEER_EID));
        adapter.tightenRateLimits(higher, true);
        vm.stopPrank();

        (, , uint256 limit, ) = adapter.outboundRateLimits(PEER_EID);
        assertEq(limit, LIMIT / 2);
    }

    function test_InitializeControls_OnlyOnceAndNotForStrangers() public {
        vm.prank(owner);
        vm.expectRevert();
        adapter.initializeControls(feeDeposit, 1 days);

        EtherfiOFTAdapterUpgradeable impl = new EtherfiOFTAdapterUpgradeable(address(weETH), address(endpoint));
        EtherfiOFTAdapterUpgradeable fresh = EtherfiOFTAdapterUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (owner, owner))
        )));
        vm.prank(user);
        vm.expectRevert(OFTControls.UnauthorizedInitializer.selector);
        fresh.initializeControls(user, 1 days);
    }
}
