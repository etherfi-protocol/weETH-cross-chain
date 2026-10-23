// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/src/auth/EnumerableRoles.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {SendParam, OFTReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";

import {EtherfiOFTUpgradeable} from "../contracts/EtherfiOFTUpgradeable.sol";
import {OFTControls} from "../contracts/OFTControls.sol";
import {PairwiseRateLimiter} from "../contracts/PairwiseRateLimiter.sol";
import {PausableUntil} from "../contracts/PausableUntil.sol";
import {OFTControlsL2Base} from "./base/OFTControlsL2Base.sol";

contract OFTControlsL2Test is OFTControlsL2Base {
    // ---------------------------------------------------------------------------------------------
    // defaults: controls are off, existing flows are unchanged
    // ---------------------------------------------------------------------------------------------

    function test_Defaults_ControlsOff() public view {
        assertEq(uint8(oft.allowlistMode()), uint8(IAllowlist.AllowlistMode.Open));
        assertEq(oft.defaultFeeBps(), 0);
        assertFalse(oft.isLanePaused(PEER_EID));
        assertEq(oft.pausedUntil(), 0);
        assertEq(oft.pauseUntilDuration(), 1 days);
        assertEq(oft.feeDeposit(), feeDeposit);
        assertEq(oft.escrow(), address(0));
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


    function test_RateLimitStorageSlotsUnchanged() public view {
        // The two rate limit mappings must stay at sequential slots 0 and 1 for existing proxies.
        bytes32 outSlot = keccak256(abi.encode(PEER_EID, uint256(0)));
        bytes32 inSlot = keccak256(abi.encode(PEER_EID, uint256(1)));
        assertEq(uint256(vm.load(address(oft), bytes32(uint256(outSlot) + 2))), LIMIT);
        assertEq(uint256(vm.load(address(oft), bytes32(uint256(inSlot) + 2))), LIMIT);
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
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Blacklist);
    }

    function test_Blacklist_OnlyBlacklisterRole() public {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(user, true);
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
        vm.expectRevert(abi.encodeWithSelector(IAllowlist.NotAllowlisted.selector, user2, IAllowlist.AllowlistMode.Blacklist));
        oft.transfer(user2, 1 ether);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IAllowlist.NotAllowlisted.selector, user2, IAllowlist.AllowlistMode.Blacklist));
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

        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(user2, false);
        vm.prank(blacklister);
        oft.setBlacklisted(params);

        vm.prank(user);
        oft.transfer(user2, 1 ether);
        assertEq(oft.balanceOf(user2), 1 ether);
    }

    function test_Whitelist_OnlyWhitelistedMove() public {
        vm.startPrank(owner);
        oft.setEscrow(escrow);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Whitelist);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);

        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](2);
        params[0] = IAllowlist.SetAllowlistParam(user, true);
        params[1] = IAllowlist.SetAllowlistParam(user2, true);
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
        emit OFTControls.CreditRedirected(user2, escrow, 25 ether);
        _receive(user2, 25 ether);

        assertEq(oft.balanceOf(user2), 0);
        assertEq(oft.balanceOf(escrow), 25 ether);
        assertEq(oft.totalSupply(), 1025 ether);
    }

    function test_CreditRedirect_EscrowCannotBeClearedWhileEnforced() public {
        _enableBlacklistMode();
        vm.prank(owner);
        vm.expectRevert(OFTControls.EscrowNotSet.selector);
        oft.setEscrow(address(0));
    }

    function test_CreditRedirect_OnlyOwnerSetsEscrow() public {
        vm.prank(blacklister);
        vm.expectRevert();
        oft.setEscrow(escrow);
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
        oft.setEscrow(escrow);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Whitelist);
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
        oft.setLanePaused(PEER_EID, true);
        assertTrue(oft.isLanePaused(PEER_EID));

        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.sendExternal(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.LanePaused.selector, PEER_EID));
        this.receiveExternal(user2, 1 ether);

        // an unrelated lane keeps working
        assertFalse(oft.isLanePaused(30102));

        vm.prank(unpauser);
        oft.setLanePaused(PEER_EID, false);
        _send(user, 1 ether, 1 ether);
    }

    function test_LanePause_RolesAreSplit() public {
        vm.prank(unpauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.setLanePaused(PEER_EID, true);

        vm.prank(pauser);
        vm.expectRevert(EnumerableRoles.EnumerableRolesUnauthorized.selector);
        oft.setLanePaused(PEER_EID, false);
    }

    // ---------------------------------------------------------------------------------------------
    // per-lane fee and enumerable lists
    // ---------------------------------------------------------------------------------------------

    function test_Fee_LaneOverrideBeatsDefault() public {
        vm.startPrank(owner);
        oft.setDefaultFeeBps(10);
        oft.setFeeBps(PEER_EID, 100, true);
        vm.stopPrank();
        assertEq(oft.getFee(PEER_EID, 100 ether), 1 ether);
        assertEq(oft.getFee(30999, 100 ether), 0.1 ether);

        OFTReceipt memory receipt = _send(user, 100 ether, 0);
        assertEq(receipt.amountReceivedLD, 99 ether);
        assertEq(oft.balanceOf(feeDeposit), 1 ether);
    }

    function test_Fee_DisabledLaneFallsBackToDefault() public {
        vm.startPrank(owner);
        oft.setDefaultFeeBps(10);
        oft.setFeeBps(PEER_EID, 100, true);
        oft.setFeeBps(PEER_EID, 100, false);
        vm.stopPrank();
        assertEq(oft.getFee(PEER_EID, 100 ether), 0.1 ether);
    }

    function test_Fee_LaneFeeIsAlsoCapped() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.FeeTooHigh.selector, uint16(101)));
        oft.setFeeBps(PEER_EID, 101, true);
    }

    function test_Fee_LaneFeeNeedsDeposit() public {
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        EtherfiOFTUpgradeable fresh = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));
        vm.prank(owner);
        vm.expectRevert(OFTControls.FeeDepositNotSet.selector);
        fresh.setFeeBps(PEER_EID, 10, true);
    }

    function test_Fee_OnlyOwnerSetsLaneFee() public {
        vm.prank(blacklister);
        vm.expectRevert();
        oft.setFeeBps(PEER_EID, 10, true);
    }

    function test_Allowlist_ListsAreEnumerable() public {
        _blacklist(user);
        _blacklist(user2);
        assertEq(oft.blacklistedCount(), 2);
        address[] memory listed = oft.getBlacklist(0, 10);
        assertEq(listed.length, 2);
        assertEq(listed[0], user);
        assertEq(listed[1], user2);

        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(user, true);
        vm.prank(whitelister);
        oft.setWhitelisted(params);
        assertEq(oft.whitelistedCount(), 1);
        assertEq(oft.getWhitelist(0, 10)[0], user);
    }

    function test_Allowlist_DoubleEntryReverts() public {
        _blacklist(user);
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(user, true);
        vm.prank(blacklister);
        vm.expectRevert(abi.encodeWithSelector(IAllowlist.AllowlistStateIdempotent.selector, user, true));
        oft.setBlacklisted(params);
    }
}
