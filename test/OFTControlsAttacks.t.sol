// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {EnumerableRoles} from "solady/src/auth/EnumerableRoles.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";

import {EtherfiOFTUpgradeable} from "../contracts/EtherfiOFTUpgradeable.sol";
import {OFTControls} from "../contracts/OFTControls.sol";
import {PairwiseRateLimiter} from "../contracts/PairwiseRateLimiter.sol";
import {PausableUntil} from "../contracts/PausableUntil.sol";
import {OFTControlsL2Base} from "./base/OFTControlsL2Base.sol";

/// @notice Tries to abuse each new control. Every test is an attack that must fail or stay bounded.
contract OFTControlsAttacksTest is OFTControlsL2Base {
    address attacker = makeAddr("attacker");
    address accomplice = makeAddr("accomplice");

    // ---------------------------------------------------------------------------------------------
    // access control
    // ---------------------------------------------------------------------------------------------

    function _setParams(address who, bool enabled) internal pure returns (IAllowlist.SetAllowlistParam[] memory params) {
        params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(who, enabled);
    }

    function _rateConfig() internal pure returns (PairwiseRateLimiter.RateLimitConfig[] memory cfg) {
        cfg = new PairwiseRateLimiter.RateLimitConfig[](1);
        cfg[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, type(uint128).max, 1);
    }

    /// @dev One entry per privileged function a stranger must never reach.
    function _privilegedCalls() internal view returns (bytes[] memory calls) {
        calls = new bytes[](21);
        uint256 n;
        calls[n++] = abi.encodeCall(OFTControls.pauseBridgeUntil, ());
        calls[n++] = abi.encodeCall(OFTControls.unpauseBridgeUntil, ());
        calls[n++] = abi.encodeCall(OFTControls.setPauseUntilDuration, (3 days));
        calls[n++] = abi.encodeCall(OFTControls.setLanePaused, (PEER_EID, true));
        calls[n++] = abi.encodeCall(OFTControls.setAllowlistMode, (IAllowlist.AllowlistMode.Whitelist));
        calls[n++] = abi.encodeCall(OFTControls.setBlacklisted, (_setParams(user, true)));
        calls[n++] = abi.encodeCall(OFTControls.setWhitelisted, (_setParams(attacker, true)));
        calls[n++] = abi.encodeCall(OFTControls.setEscrow, (attacker));
        calls[n++] = abi.encodeCall(OFTControls.setFeeDeposit, (attacker));
        calls[n++] = abi.encodeCall(OFTControls.setDefaultFeeBps, (100));
        calls[n++] = abi.encodeCall(OFTControls.setFeeBps, (PEER_EID, 100, true));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.recoverFunds, (user, attacker, 1 ether));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.mint, (attacker, 1 ether));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.pauseBridge, ());
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.unpauseBridge, ());
        calls[n++] = abi.encodeCall(EnumerableRoles.setRole, (attacker, 1, true));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.setOutboundRateLimits, (_rateConfig()));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.setInboundRateLimits, (_rateConfig()));
        calls[n++] = abi.encodeCall(EtherfiOFTUpgradeable.updateTokenSymbol, ("x", "x"));
        calls[n++] = abi.encodeWithSignature("setPeer(uint32,bytes32)", PEER_EID, bytes32(uint256(uint160(attacker))));
        calls[n++] = abi.encodeWithSignature("setMsgInspector(address)", attacker);
    }

    function test_Attacker_CannotCallAnyPrivilegedFunction() public {
        bytes[] memory calls = _privilegedCalls();
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(attacker);
            (bool ok, ) = address(oft).call(calls[i]);
            assertFalse(ok, string.concat("attacker reached privileged call #", vm.toString(i)));
        }
    }

    function test_RoleHolders_CannotReachOtherRolesFunctions() public {
        // blacklister cannot whitelist, pause, unpause, or touch config
        vm.startPrank(blacklister);
        (bool ok, ) = address(oft).call(abi.encodeCall(OFTControls.setWhitelisted, (_setParams(user, true))));
        assertFalse(ok, "blacklister whitelisted");
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.setLanePaused, (PEER_EID, true)));
        assertFalse(ok, "blacklister paused a lane");
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.setFeeBps, (PEER_EID, 1, true)));
        assertFalse(ok, "blacklister set a fee");
        (ok, ) = address(oft).call(abi.encodeCall(EnumerableRoles.setRole, (blacklister, 1, true)));
        assertFalse(ok, "blacklister granted itself a role");
        vm.stopPrank();

        // guardian cannot unpause, blacklist, or move lanes
        vm.startPrank(guardian);
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.unpauseBridgeUntil, ()));
        assertFalse(ok, "guardian unpaused");
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.setBlacklisted, (_setParams(user, true))));
        assertFalse(ok, "guardian blacklisted");
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.setLanePaused, (PEER_EID, false)));
        assertFalse(ok, "guardian touched a lane");
        vm.stopPrank();

        // whitelister cannot blacklist
        vm.prank(whitelister);
        (ok, ) = address(oft).call(abi.encodeCall(OFTControls.setBlacklisted, (_setParams(user, true))));
        assertFalse(ok, "whitelister blacklisted");
    }

    function test_ImplementationCannotBeInitialized() public {
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize("x", "x", attacker);
    }

    function test_ProxyCannotBeReinitialized() public {
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oft.initialize("x", "x", attacker);
    }

    // ---------------------------------------------------------------------------------------------
    // guardian pause
    // ---------------------------------------------------------------------------------------------

    function test_Guardian_CannotExtendAnActivePause() public {
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        uint256 until = oft.pausedUntil();
        vm.warp(block.timestamp + 12 hours);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        oft.pauseBridgeUntil();
        assertEq(oft.pausedUntil(), until);
    }

    function test_Guardian_PauseNeverOutlivesTheConfiguredDuration() public {
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        vm.warp(oft.pausedUntil() + 1);
        // the bridge works again with no action from anyone
        _send(user, 1 ether, 1 ether);
    }

    /// @dev The cooldown is per address. Two guardian holders can pause back to back, so grant the role to one Safe.
    function test_Known_SecondGuardianCanRepauseAtExpiry() public {
        address guardian2 = makeAddr("guardian2");
        vm.prank(owner);
        oft.setRole(guardian2, PAUSER_UNTIL_ROLE, true);

        vm.prank(guardian);
        oft.pauseBridgeUntil();
        vm.warp(oft.pausedUntil() + 1);
        vm.prank(guardian2);
        oft.pauseBridgeUntil();
        assertGt(oft.pausedUntil(), block.timestamp);

        // one address alone is locked out by its own cooldown...
        uint256 until = oft.pausedUntil();
        vm.prank(guardian2);
        vm.expectRevert(abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, until));
        oft.pauseBridgeUntil();

        // ...but two holders keep taking turns, so only the UNPAUSER role ends the chain
        vm.warp(oft.pausedUntil() + 1);
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        assertGt(oft.pausedUntil(), block.timestamp);
        vm.prank(unpauser);
        oft.unpauseBridgeUntil();
        _send(user, 1 ether, 1 ether);
    }

    function test_Pauses_DoNotFreezeTokenTransfersOrMinting() public {
        vm.prank(guardian);
        oft.pauseBridgeUntil();
        vm.prank(pauser);
        oft.pauseBridge();
        vm.prank(user);
        oft.transfer(user2, 1 ether);
        vm.prank(minter);
        oft.mint(user2, 1 ether);
        assertEq(oft.balanceOf(user2), 2 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // fee
    // ---------------------------------------------------------------------------------------------

    function testFuzz_Fee_AccountingAlwaysBalances(uint96 rawAmount, uint16 rawBps) public {
        uint256 amount = bound(uint256(rawAmount), 1e12, 900 ether);
        uint16 bps = uint16(bound(uint256(rawBps), 0, 100));
        vm.prank(owner);
        oft.setDefaultFeeBps(bps);
        uint256 supplyBefore = oft.totalSupply();

        OFTReceipt memory receipt = _send(user, amount, 0);
        uint256 fee = oft.balanceOf(feeDeposit);

        assertEq(receipt.amountSentLD, receipt.amountReceivedLD + fee, "sent != received + fee");
        assertEq(receipt.amountReceivedLD % 1e12, 0, "received has dust");
        assertGe(fee, (receipt.amountSentLD * bps) / 10_000, "fee below the configured rate");
        assertLe(fee, (receipt.amountSentLD * bps) / 10_000 + 1e12, "fee above rate plus one dust unit");
        assertEq(supplyBefore - oft.totalSupply(), receipt.amountReceivedLD, "supply must drop by what the peer mints");
    }

    function testFuzz_Fee_NeverAboveCap(uint16 bps) public {
        vm.assume(bps > 100);
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.FeeTooHigh.selector, bps));
        oft.setDefaultFeeBps(bps);
        vm.expectRevert(abi.encodeWithSelector(OFTControls.FeeTooHigh.selector, bps));
        oft.setFeeBps(PEER_EID, bps, true);
        vm.stopPrank();
    }

    function test_Fee_RateLimitCountsTheFullAmount() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(100);
        vm.prank(minter);
        oft.mint(user, LIMIT);
        vm.expectRevert(PairwiseRateLimiter.OutboundRateLimitExceeded.selector);
        this.sendExternal(user, LIMIT + 1 ether);
    }

    function test_Fee_BlockedFeeDepositCannotStopBridging() public {
        vm.prank(owner);
        oft.setDefaultFeeBps(50);
        _enableBlacklistMode();
        _blacklist(feeDeposit);
        _send(user, 10 ether, 0);
        assertEq(oft.balanceOf(feeDeposit), 0.05 ether);
    }

    function test_Fee_BlockedEscrowCannotStopInbound() public {
        _enableBlacklistMode();
        _blacklist(escrow);
        _blacklist(user2);
        _receive(user2, 5 ether);
        assertEq(oft.balanceOf(escrow), 5 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // blacklist evasion
    // ---------------------------------------------------------------------------------------------

    function test_Evasion_BlockedHolderCannotMoveBySelfOrThroughAFriend() public {
        _enableBlacklistMode();
        _blacklist(user);

        vm.prank(user);
        vm.expectRevert();
        oft.transfer(accomplice, 1 ether);

        // a blocked holder cannot pull its own tokens through an approval it gave to an accomplice
        vm.prank(user);
        oft.approve(accomplice, type(uint256).max);
        vm.prank(accomplice);
        vm.expectRevert();
        oft.transferFrom(user, accomplice, 1 ether);

        // and cannot bridge out
        vm.expectRevert();
        this.sendExternal(user, 1 ether);
        assertEq(oft.balanceOf(user), 1000 ether);
    }

    function test_Evasion_NobodyCanSendToABlockedHolder() public {
        _enableBlacklistMode();
        _blacklist(user2);
        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);

        vm.prank(user);
        oft.approve(accomplice, 5 ether);
        vm.prank(accomplice);
        vm.expectRevert();
        oft.transferFrom(user, user2, 1 ether);
    }

    function test_Evasion_InboundForABlockedHolderNeverReachesIt() public {
        _enableBlacklistMode();
        _blacklist(user2);
        _receive(user2, 7 ether);
        assertEq(oft.balanceOf(user2), 0);
        assertEq(oft.balanceOf(escrow), 7 ether);
        assertEq(oft.totalSupply(), 1007 ether);
    }

    function test_Evasion_WhitelistModeBlocksEveryoneNotListed() public {
        vm.startPrank(owner);
        oft.setEscrow(escrow);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Whitelist);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);
        vm.expectRevert();
        this.sendExternal(user, 1 ether);
        _receive(user2, 3 ether);
        assertEq(oft.balanceOf(escrow), 3 ether);
    }

    function test_Evasion_BlacklistAddedWhileOpenDoesNothingUntilModeFlips() public {
        _blacklist(user);
        vm.prank(user);
        oft.transfer(user2, 1 ether);
        _enableBlacklistMode();
        vm.prank(user);
        vm.expectRevert();
        oft.transfer(user2, 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // recoverFunds
    // ---------------------------------------------------------------------------------------------

    function test_Recover_CannotTouchAnUnlistedHolderInAnyMode() public {
        // Open
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user));
        oft.recoverFunds(user, owner, 1 ether);

        // Blacklist, holder not listed
        _enableBlacklistMode();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user));
        oft.recoverFunds(user, owner, 1 ether);
    }

    function test_Recover_CannotBurnOrOverdraw() public {
        _enableBlacklistMode();
        _blacklist(user);
        vm.startPrank(owner);
        vm.expectRevert();
        oft.recoverFunds(user, address(0), 1 ether);
        vm.expectRevert();
        oft.recoverFunds(user, owner, 1001 ether);
        vm.stopPrank();
        assertEq(oft.totalSupply(), 1000 ether);
    }

    function test_Recover_StopsOnceTheHolderIsCleared() public {
        _enableBlacklistMode();
        _blacklist(user);
        vm.prank(blacklister);
        oft.setBlacklisted(_setParams(user, false));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherfiOFTUpgradeable.CannotRecoverFrom.selector, user));
        oft.recoverFunds(user, owner, 1 ether);
    }

    function test_Recover_BlacklisterCannotRecover() public {
        _enableBlacklistMode();
        _blacklist(user);
        vm.prank(blacklister);
        vm.expectRevert();
        oft.recoverFunds(user, blacklister, 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // supply
    // ---------------------------------------------------------------------------------------------

    /// @dev Random sends and receives, with a fee and a blocked recipient, never create or lose supply.
    function testFuzz_Supply_FollowsWhatThePeerMints(uint96[6] memory amounts, uint8[6] memory ops, uint16 rawBps) public {
        vm.prank(owner);
        oft.setDefaultFeeBps(uint16(bound(uint256(rawBps), 0, 100)));
        _enableBlacklistMode();
        _blacklist(user2);

        uint256 expected = oft.totalSupply();
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = bound(uint256(amounts[i]), 1e12, 50 ether);
            if (ops[i] % 3 == 0 && oft.balanceOf(user) >= amount) {
                OFTReceipt memory receipt = _send(user, amount, 0);
                expected -= receipt.amountReceivedLD; // the peer mints this much
            } else if (ops[i] % 3 == 1) {
                _receive(user, amount - (amount % 1e12));
                expected += amount - (amount % 1e12);
            } else {
                _receive(user2, amount - (amount % 1e12)); // redirected to escrow, still minted once
                expected += amount - (amount % 1e12);
            }
            assertEq(oft.totalSupply(), expected, "supply drifted");
        }
        assertEq(oft.balanceOf(user2), 0, "blocked holder got tokens");
    }
}
