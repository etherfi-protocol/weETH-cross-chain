// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/src/auth/EnumerableRoles.sol";
import {ICreditRedirect} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/ICreditRedirect.sol";
import {SendParam, OFTReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";

import {EtherfiOFTUpgradeable} from "../contracts/EtherfiOFTUpgradeable.sol";
import {OFTControls} from "../contracts/OFTControls.sol";
import {PairwiseRateLimiter} from "../contracts/PairwiseRateLimiter.sol";
import {PausableUntil} from "../contracts/PausableUntil.sol";
import {OFTEndpointMock} from "./mock/OFTEndpointMock.sol";

contract OFTControlsL2Test is Test {
    uint32 constant PEER_EID = 30101;
    uint256 constant BLACKLISTER_ROLE = 4;
    uint256 constant WHITELISTER_ROLE = 5;
    uint256 constant RATE_LIMIT_MANAGER_ROLE = 6;
    uint256 constant PAUSER_UNTIL_ROLE = 7;
    uint256 constant LIMIT = 1_000_000 ether;
    uint256 constant WINDOW = 1 days;

    OFTEndpointMock endpoint;
    EtherfiOFTUpgradeable oft;

    address owner = makeAddr("owner");
    address minter = makeAddr("minter");
    address pauser = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address guardian = makeAddr("guardian");
    address blacklister = makeAddr("blacklister");
    address whitelister = makeAddr("whitelister");
    address rateManager = makeAddr("rateManager");
    address feeDeposit = makeAddr("feeDeposit");
    address escrow = makeAddr("escrow");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    bytes32 peer = bytes32(uint256(uint160(makeAddr("peer"))));

    function setUp() public {
        vm.warp(1_800_000_000);
        endpoint = new OFTEndpointMock(30184);
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        oft = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));

        PairwiseRateLimiter.RateLimitConfig[] memory limits = new PairwiseRateLimiter.RateLimitConfig[](1);
        limits[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, LIMIT, WINDOW);

        vm.startPrank(owner);
        oft.initializeControls(feeDeposit, 1 days);
        oft.setPeer(PEER_EID, peer);
        oft.setOutboundRateLimits(limits);
        oft.setInboundRateLimits(limits);
        oft.setRole(minter, oft.MINTER_ROLE(), true);
        oft.setRole(pauser, oft.PAUSER_ROLE(), true);
        oft.setRole(unpauser, oft.UNPAUSER_ROLE(), true);
        oft.setRole(guardian, PAUSER_UNTIL_ROLE, true);
        oft.setRole(blacklister, BLACKLISTER_ROLE, true);
        oft.setRole(whitelister, WHITELISTER_ROLE, true);
        oft.setRole(rateManager, RATE_LIMIT_MANAGER_ROLE, true);
        vm.stopPrank();

        vm.prank(minter);
        oft.mint(user, 1000 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------------

    function _send(address from, uint256 amount, uint256 minAmount) internal returns (OFTReceipt memory receipt) {
        SendParam memory param = SendParam(PEER_EID, bytes32(uint256(uint160(from))), amount, minAmount, "", "", "");
        MessagingFee memory fee = oft.quoteSend(param, false);
        vm.deal(from, 1 ether);
        vm.prank(from);
        (, receipt) = oft.send{value: fee.nativeFee}(param, fee, from);
    }

    function _receive(address to, uint256 amountLD) internal {
        Origin memory origin = Origin(PEER_EID, peer, 1);
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(to))), uint64(amountLD / 1e12));
        vm.prank(address(endpoint));
        oft.lzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function _blacklist(address account) internal {
        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](1);
        params[0] = OFTControls.SetAllowlistParam(account, true);
        vm.prank(blacklister);
        oft.setBlacklisted(params);
    }

    function _enableBlacklistMode() internal {
        vm.startPrank(owner);
        oft.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(address(oft), escrow));
        oft.setAllowlistMode(OFTControls.AllowlistMode.Blacklist);
        vm.stopPrank();
    }

    function _encodeEids(uint32 eid) internal pure returns (uint32[] memory eids) {
        eids = new uint32[](1);
        eids[0] = eid;
    }

    // ---------------------------------------------------------------------------------------------
    // defaults: controls are off, existing flows are unchanged
    // ---------------------------------------------------------------------------------------------

    function test_Defaults_ControlsOff() public view {
        assertEq(uint8(oft.allowlistMode()), uint8(OFTControls.AllowlistMode.Open));
        assertEq(oft.defaultFeeBps(), 0);
        assertFalse(oft.isLanePaused(PEER_EID));
        assertEq(oft.pausedUntil(), 0);
        assertEq(oft.pauseUntilDuration(), 1 days);
        assertEq(oft.feeDeposit(), feeDeposit);
        assertTrue(oft.isAllowlisted(user));
    }

    function test_Defaults_SendBurnsAndReceiveMints() public {
        OFTReceipt memory receipt = _send(user, 100 ether, 100 ether);
        assertEq(receipt.amountSentLD, 100 ether);
        assertEq(receipt.amountReceivedLD, 100 ether);
        assertEq(oft.balanceOf(user), 900 ether);
        assertEq(oft.totalSupply(), 900 ether);

        _receive(user2, 40 ether);
        assertEq(oft.balanceOf(user2), 40 ether);
    }

    function test_Defaults_ExistingRateLimitStillEnforced() public {
        vm.prank(minter);
        oft.mint(user, LIMIT);
        vm.expectRevert(PairwiseRateLimiter.OutboundRateLimitExceeded.selector);
        this.sendExternal(user, LIMIT + 1 ether);
    }

    function sendExternal(address from, uint256 amount) external {
        _send(from, amount, 0);
    }

    function test_RateLimitStorageSlotsUnchanged() public view {
        // The two rate limit mappings must stay at sequential slots 0 and 1 for existing proxies.
        bytes32 outSlot = keccak256(abi.encode(PEER_EID, uint256(0)));
        bytes32 inSlot = keccak256(abi.encode(PEER_EID, uint256(1)));
        assertEq(uint256(vm.load(address(oft), bytes32(uint256(outSlot) + 2))), LIMIT);
        assertEq(uint256(vm.load(address(oft), bytes32(uint256(inSlot) + 2))), LIMIT);
    }

    // ---------------------------------------------------------------------------------------------
    // initializeControls
    // ---------------------------------------------------------------------------------------------

    function test_InitializeControls_OnlyOnce() public {
        vm.prank(owner);
        vm.expectRevert();
        oft.initializeControls(feeDeposit, 1 days);
    }

    function test_InitializeControls_RejectsStrangers() public {
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        EtherfiOFTUpgradeable fresh = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));
        vm.prank(user);
        vm.expectRevert(OFTControls.UnauthorizedInitializer.selector);
        fresh.initializeControls(user, 1 days);
    }

    // ---------------------------------------------------------------------------------------------
    // bridge fee
    // ---------------------------------------------------------------------------------------------

    function test_Fee_SplitsSentAmountAndMintsFee() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(50);

        OFTReceipt memory receipt = _send(user, 100 ether, 99 ether);
        assertEq(receipt.amountSentLD, 100 ether);
        assertEq(receipt.amountReceivedLD, 99.5 ether);
        assertEq(oft.balanceOf(feeDeposit), 0.5 ether);
        assertEq(oft.balanceOf(user), 900 ether);
        // supply drops by what the destination mints
        assertEq(oft.totalSupply(), 900.5 ether);
        // destination amount in the message is the post-fee amount in shared decimals
        bytes memory message = endpoint.lastMessage();
        uint64 amountSD;
        assembly {
            amountSD := shr(192, mload(add(message, 64)))
        }
        assertEq(uint256(amountSD) * 1e12, 99.5 ether);
    }

    function test_Fee_DustComesOutOfFee() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(50);

        uint256 amount = 1 ether + 3e12 + 7;
        OFTReceipt memory receipt = _send(user, amount, 0);
        assertEq(receipt.amountSentLD, 1 ether + 3e12);
        assertEq(receipt.amountReceivedLD % 1e12, 0);
        assertEq(oft.balanceOf(feeDeposit), receipt.amountSentLD - receipt.amountReceivedLD);
        assertGe(oft.balanceOf(feeDeposit), (receipt.amountSentLD * 50) / 10_000);
    }

    function test_Fee_SlippageProtectionTrips() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(50);
        vm.expectRevert();
        this.sendExternalWithMin(user, 100 ether, 100 ether);
    }

    function sendExternalWithMin(address from, uint256 amount, uint256 minAmount) external {
        _send(from, amount, minAmount);
    }

    function test_Fee_QuoteOFTShowsFee() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(100);
        SendParam memory param = SendParam(PEER_EID, bytes32(uint256(1)), 100 ether, 0, "", "", "");
        (, , OFTReceipt memory receipt) = oft.quoteOFT(param);
        assertEq(receipt.amountReceivedLD, 99 ether);
    }

    function test_Fee_CappedAndNeedsDeposit() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.FeeTooHigh.selector, uint16(101)));
        oft.setDefaultFeeBps(101);
        oft.setDefaultFeeBps(100);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        oft.setDefaultFeeBps(1);
    }

    function test_Fee_NeedsDepositBeforeEnable() public {
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        EtherfiOFTUpgradeable fresh = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));
        vm.prank(owner);
        vm.expectRevert(OFTControls.FeeDepositNotSet.selector);
        fresh.setDefaultFeeBps(10);
    }

    // ---------------------------------------------------------------------------------------------
    // blacklist / whitelist
    // ---------------------------------------------------------------------------------------------

    function test_Blacklist_ModeNeedsEscrow() public {
        vm.prank(owner);
        vm.expectRevert(OFTControls.EscrowNotSet.selector);
        oft.setAllowlistMode(OFTControls.AllowlistMode.Blacklist);
    }

    function test_Blacklist_OnlyBlacklisterRole() public {
        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](1);
        params[0] = OFTControls.SetAllowlistParam(user, true);
        vm.prank(user);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.setBlacklisted(params);
    }

    function test_Blacklist_EntriesDoNothingWhileOpen() public {
        _blacklist(user2);
        assertTrue(oft.isBlacklisted(user2));
        assertTrue(oft.isAllowlisted(user2));
        vm.prank(user);
        oft.transfer(user2, 1 ether);
    }

    function test_Blacklist_BlocksTransferMintAndSend() public {
        _blacklist(user2);
        _enableBlacklistMode();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.NotAllowlisted.selector, user2, OFTControls.AllowlistMode.Blacklist));
        oft.transfer(user2, 1 ether);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.NotAllowlisted.selector, user2, OFTControls.AllowlistMode.Blacklist));
        oft.mint(user2, 1 ether);

        // a blacklisted holder cannot move tokens or bridge them out
        vm.prank(minter);
        oft.mint(user, 1 ether);
        _blacklist(user);
        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);
        vm.expectRevert();
        this.sendExternal(user, 1 ether);
    }

    function test_Blacklist_BlocksBlacklistedSpender() public {
        _enableBlacklistMode();
        vm.prank(user);
        oft.approve(user2, 10 ether);
        _blacklist(user2);
        vm.prank(user2);
        vm.expectRevert();
        oft.transferFrom(user, user2, 1 ether);
    }

    function test_Blacklist_UnblacklistRestoresAccess() public {
        _enableBlacklistMode();
        _blacklist(user2);

        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](1);
        params[0] = OFTControls.SetAllowlistParam(user2, false);
        vm.prank(blacklister);
        oft.setBlacklisted(params);

        vm.prank(user);
        oft.transfer(user2, 1 ether);
        assertEq(oft.balanceOf(user2), 1 ether);
    }

    function test_Whitelist_OnlyWhitelistedMove() public {
        vm.startPrank(owner);
        oft.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(address(oft), escrow));
        oft.setAllowlistMode(OFTControls.AllowlistMode.Whitelist);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);

        OFTControls.SetAllowlistParam[] memory params = new OFTControls.SetAllowlistParam[](2);
        params[0] = OFTControls.SetAllowlistParam(user, true);
        params[1] = OFTControls.SetAllowlistParam(user2, true);
        vm.prank(whitelister);
        oft.setWhitelisted(params);

        vm.prank(user);
        oft.transfer(user2, 1 ether);
        assertEq(oft.balanceOf(user2), 1 ether);
    }

    function test_CreditRedirect_BlockedRecipientGoesToEscrow() public {
        _enableBlacklistMode();
        _blacklist(user2);

        vm.expectEmit(true, true, false, true, address(oft));
        emit ICreditRedirect.CreditRedirected(user2, escrow, 25 ether);
        _receive(user2, 25 ether);

        assertEq(oft.balanceOf(user2), 0);
        assertEq(oft.balanceOf(escrow), 25 ether);
        assertEq(oft.totalSupply(), 1025 ether);
    }

    function test_CreditRedirect_EscrowCannotBeClearedWhileEnforced() public {
        _enableBlacklistMode();
        vm.prank(owner);
        vm.expectRevert(OFTControls.EscrowNotSet.selector);
        oft.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(address(0), address(0)));
    }

    function test_CreditRedirect_RejectsForeignAllowlist() public {
        vm.prank(owner);
        vm.expectRevert(ICreditRedirect.InvalidCreditRedirectConfig.selector);
        oft.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(makeAddr("other"), escrow));
    }

    // ---------------------------------------------------------------------------------------------
    // recoverFunds
    // ---------------------------------------------------------------------------------------------

    function test_Recover_OnlyFromBlacklistedInBlacklistMode() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user));
        oft.recoverFunds(user, owner, 1 ether);

        _enableBlacklistMode();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user));
        oft.recoverFunds(user, owner, 1 ether);

        _blacklist(user);
        vm.expectEmit(true, true, false, true, address(oft));
        emit EtherfiOFTUpgradeable.FundsRecovered(user, escrow, 400 ether);
        vm.prank(owner);
        oft.recoverFunds(user, escrow, 400 ether);

        assertEq(oft.balanceOf(user), 600 ether);
        assertEq(oft.balanceOf(escrow), 400 ether);
    }

    function test_Recover_NotPossibleInWhitelistMode() public {
        _blacklist(user);
        vm.startPrank(owner);
        oft.setCreditRedirectConfig(ICreditRedirect.CreditRedirectConfig(address(oft), escrow));
        oft.setAllowlistMode(OFTControls.AllowlistMode.Whitelist);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user2));
        oft.recoverFunds(user2, owner, 0);
        vm.stopPrank();
    }

    function test_Recover_OnlyOwner() public {
        _enableBlacklistMode();
        _blacklist(user);
        vm.prank(blacklister);
        vm.expectRevert();
        oft.recoverFunds(user, blacklister, 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // pause until (guardian) and per-lane pause
    // ---------------------------------------------------------------------------------------------

    function test_PauseUntil_StopsBridgeThenExpires() public {
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        uint256 until = oft.pausedUntil();
        assertEq(until, block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        this.sendExternal(user, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        this.receiveExternal(user2, 1 ether);

        vm.warp(until + 1);
        _send(user, 1 ether, 1 ether);
        _receive(user2, 1 ether);
    }

    function receiveExternal(address to, uint256 amount) external {
        _receive(to, amount);
    }

    function test_PauseUntil_UnpauserCanEndEarly() public {
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        vm.prank(unpauser);
        oft.unpauseBridgeUntil();
        _send(user, 1 ether, 1 ether);
    }

    function test_PauseUntil_GuardianCannotRepause() public {
        vm.startPrank(guardian);
        oft.pauseBridgeUntil();
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(PausableUntil.PauserCooldownStillActive.selector);
        oft.pauseBridgeUntil();
        vm.warp(block.timestamp + 1 days);
        oft.pauseBridgeUntil();
        vm.stopPrank();
    }

    function test_PauseUntil_GuardianCannotUseIndefinitePause() public {
        vm.prank(guardian);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.pauseBridge();
    }

    function test_PauseUntil_OnlyGuardianRole() public {
        vm.prank(pauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.pauseBridgeUntil();
    }

    function test_PauseUntil_DurationBoundsAndOwnerOnly() public {
        vm.startPrank(owner);
        vm.expectRevert(PausableUntil.InvalidPauseUntilDuration.selector);
        oft.setPauseUntilDuration(1 hours);
        vm.expectRevert(PausableUntil.InvalidPauseUntilDuration.selector);
        oft.setPauseUntilDuration(4 days);
        oft.setPauseUntilDuration(12 hours);
        vm.stopPrank();
        assertEq(oft.pauseUntilDuration(), 12 hours);

        vm.prank(guardian);
        vm.expectRevert();
        oft.setPauseUntilDuration(1 days);
    }

    function test_PauseUntil_NeedsDurationConfigured() public {
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        EtherfiOFTUpgradeable fresh = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));
        vm.startPrank(owner);
        fresh.setRole(guardian, PAUSER_UNTIL_ROLE, true);
        vm.stopPrank();
        vm.prank(guardian);
        vm.expectRevert(OFTControls.PauseUntilDurationNotSet.selector);
        fresh.pauseBridgeUntil();
    }

    function test_GlobalPause_StillWorks() public {
        vm.prank(pauser);
        oft.pauseBridge();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        this.sendExternal(user, 1 ether);
        vm.prank(unpauser);
        oft.unpauseBridge();
        _send(user, 1 ether, 1 ether);
    }

    function test_LanePause_BlocksOnlyThatLane() public {
        vm.prank(pauser);
        oft.pauseLanes(_encodeEids(PEER_EID));
        assertTrue(oft.isLanePaused(PEER_EID));

        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.sendExternal(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.receiveExternal(user2, 1 ether);

        // an unrelated lane keeps working
        assertFalse(oft.isLanePaused(30102));

        vm.prank(unpauser);
        oft.unpauseLanes(_encodeEids(PEER_EID));
        _send(user, 1 ether, 1 ether);
    }

    function test_LanePause_RolesAreSplit() public {
        vm.prank(unpauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.pauseLanes(_encodeEids(PEER_EID));

        vm.prank(pauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.unpauseLanes(_encodeEids(PEER_EID));
    }

    // ---------------------------------------------------------------------------------------------
    // rate limit manager (tighten only)
    // ---------------------------------------------------------------------------------------------

    function _config(uint32 eid, uint256 limit, uint256 window) internal pure returns (PairwiseRateLimiter.RateLimitConfig[] memory cfg) {
        cfg = new PairwiseRateLimiter.RateLimitConfig[](1);
        cfg[0] = PairwiseRateLimiter.RateLimitConfig(eid, limit, window);
    }

    function test_Tighten_ManagerCanLowerBothDirections() public {
        vm.startPrank(rateManager);
        oft.tightenRateLimits(_config(PEER_EID, LIMIT / 2, WINDOW), true);
        oft.tightenRateLimits(_config(PEER_EID, LIMIT, WINDOW * 2), false);
        vm.stopPrank();

        (, , uint256 outLimit, ) = oft.outboundRateLimits(PEER_EID);
        (, , uint256 inLimit, uint256 inWindow) = oft.inboundRateLimits(PEER_EID);
        assertEq(outLimit, LIMIT / 2);
        assertEq(inLimit, LIMIT);
        assertEq(inWindow, WINDOW * 2);
    }

    function test_Tighten_ManagerCanZeroALane() public {
        vm.prank(rateManager);
        oft.tightenRateLimits(_config(PEER_EID, 0, WINDOW), true);
        vm.expectRevert(PairwiseRateLimiter.OutboundRateLimitExceeded.selector);
        this.sendExternal(user, 1 ether);
    }

    function test_Tighten_ManagerCannotLoosen() public {
        vm.startPrank(rateManager);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.RateLimitNotTightening.selector, PEER_EID));
        oft.tightenRateLimits(_config(PEER_EID, LIMIT + 1, WINDOW), true);
        // same limit over a shorter window is a faster rate
        vm.expectRevert(abi.encodeWithSelector(OFTControls.RateLimitNotTightening.selector, PEER_EID));
        oft.tightenRateLimits(_config(PEER_EID, LIMIT, WINDOW / 2), true);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.RateLimitNotTightening.selector, PEER_EID));
        oft.tightenRateLimits(_config(PEER_EID, 1, 0), true);
        vm.stopPrank();
    }

    function test_Tighten_ManagerCannotEnableNewPeer() public {
        vm.prank(rateManager);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.RateLimitNotTightening.selector, uint32(30999)));
        oft.tightenRateLimits(_config(30999, 1 ether, WINDOW), true);
    }

    function test_Tighten_OnlyManagerRole() public {
        vm.prank(pauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.tightenRateLimits(_config(PEER_EID, 1, WINDOW), true);
    }

    function test_Tighten_ManagerCannotUseOwnerSetters() public {
        vm.prank(rateManager);
        vm.expectRevert();
        oft.setOutboundRateLimits(_config(PEER_EID, LIMIT * 2, WINDOW));
    }

    function test_Tighten_OwnerKeepsFullControl() public {
        vm.prank(owner);
        oft.setOutboundRateLimits(_config(PEER_EID, LIMIT * 2, WINDOW));
        (, , uint256 limit, ) = oft.outboundRateLimits(PEER_EID);
        assertEq(limit, LIMIT * 2);
    }
}
