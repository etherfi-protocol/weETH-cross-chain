// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EtherfiL1SyncPoolETH} from "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import {PausableUntil} from "../contracts/PausableUntil.sol";
import {Constants} from "../contracts/libraries/Constants.sol";

import {SimpleEndpointMock} from "./mock/SimpleEndpointMock.sol";
import {MockRoleRegistry} from "./mock/MockRoleRegistry.sol";

/// @dev Exposes the internal deposit hooks so the pause guard can be exercised
/// directly without standing up the full LayerZero / liquifier dependency graph.
contract EtherfiL1SyncPoolETHHarness is EtherfiL1SyncPoolETH {
    constructor(address endpoint, address roleRegistry)
        EtherfiL1SyncPoolETH(endpoint, roleRegistry)
    {}

    function exposed_anticipatedDeposit(
        uint32 originEid,
        bytes32 guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256) {
        return _anticipatedDeposit(originEid, guid, tokenIn, amountIn, amountOut);
    }

    function exposed_finalizeDeposit(
        uint32 originEid,
        bytes32 guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) external payable {
        _finalizeDeposit(originEid, guid, tokenIn, amountIn, amountOut);
    }

    function exposed_pauseUntil() external {
        _pauseUntil();
    }

    function exposed_unpauseUntil() external {
        _unpauseUntil();
    }

    function exposed_setPauseUntilDuration(uint256 duration) external {
        _setPauseUntilDuration(duration);
    }

    function exposed_pausedUntil() external view returns (uint256) {
        return _getPausableUntilStorage().pausedUntil;
    }

    function exposed_lastPauseTimestamp(address account) external view returns (uint256) {
        return _getPausableUntilStorage().lastPauseTimestamp[account];
    }
}

contract EtherfiL1SyncPoolETHPauseTest is Test {
    EtherfiL1SyncPoolETHHarness internal syncPool;
    SimpleEndpointMock internal endpoint;
    MockRoleRegistry internal roleRegistry;

    address internal owner = makeAddr("owner");
    address internal admin = makeAddr("admin");
    address internal guardian = makeAddr("guardian");
    address internal stranger = makeAddr("stranger");
    address internal liquifier = makeAddr("liquifier");
    address internal eEth = makeAddr("eEth");
    address internal tokenOut = makeAddr("tokenOut");
    address internal lockBox = makeAddr("lockBox");

    event Paused();
    event Unpaused();
    event PausedUntil(uint256 pausedUntil);
    event UnpausedUntil();
    event PauseUntilDurationSet(uint256 pauseUntilDuration);

    function setUp() public {
        endpoint = new SimpleEndpointMock(1);
        roleRegistry = new MockRoleRegistry(owner);

        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.GUARDIAN_ROLE(), guardian);
        roleRegistry.grantRole(roleRegistry.OPERATION_MULTISIG_ROLE(), admin);
        vm.stopPrank();

        EtherfiL1SyncPoolETHHarness impl =
            new EtherfiL1SyncPoolETHHarness(address(endpoint), address(roleRegistry));
        syncPool = EtherfiL1SyncPoolETHHarness(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(
                        EtherfiL1SyncPoolETH.initialize.selector,
                        liquifier,
                        eEth,
                        tokenOut,
                        lockBox,
                        owner
                    )
                )
            )
        );

        // Configure pause duration to MAX_PAUSE_DURATION so cooldown math in
        // the tests below (which references the constant) stays consistent.
        syncPool.exposed_setPauseUntilDuration(syncPool.MAX_PAUSE_DURATION());

        vm.deal(address(this), 100 ether);

        // Move past the initial cooldown window. `_pauseUntil` checks
        // `lastPauseTimestamp + pauseUntilDuration + PAUSER_UNTIL_COOLDOWN > block.timestamp`,
        // which evaluates `0 + 4 days > 1` at Foundry's default timestamp and
        // would block the very first call. Warping here makes the cooldown
        // sensible for fresh callers and gives later tests room to subtract.
        vm.warp(30 days);
    }

    // -----------------------------------------------------------------
    // Access control
    // -----------------------------------------------------------------

    function test_Pause_OnlyOperatingMultisig() public {
        vm.prank(stranger);
        vm.expectRevert(MockRoleRegistry.OnlyOperatingMultisig.selector);
        syncPool.pause();
    }

    function test_Unpause_OnlyOperatingMultisig() public {
        vm.prank(admin);
        syncPool.pause();

        vm.prank(stranger);
        vm.expectRevert(MockRoleRegistry.OnlyOperatingMultisig.selector);
        syncPool.unpause();
    }

    function test_PauseUntil_OnlyGuardian() public {
        vm.prank(stranger);
        vm.expectRevert(MockRoleRegistry.OnlyGuardian.selector);
        syncPool.pauseUntil();
    }

    function test_UnpauseUntil_OnlyOperatingMultisig() public {
        vm.prank(guardian);
        syncPool.pauseUntil();

        vm.prank(stranger);
        vm.expectRevert(MockRoleRegistry.OnlyOperatingMultisig.selector);
        syncPool.unpauseUntil();
    }

    function test_SetPauseUntilDuration_OnlyOperatingTimelock() public {
        vm.prank(stranger);
        vm.expectRevert(MockRoleRegistry.OnlyOperatingTimelock.selector);
        syncPool.setPauseUntilDuration(1 days);
    }

    // -----------------------------------------------------------------
    // State transitions + events
    // -----------------------------------------------------------------

    function test_Pause_EmitsEvent() public {
        vm.expectEmit(false, false, false, false, address(syncPool));
        emit Paused();
        vm.prank(admin);
        syncPool.pause();
    }

    function test_Unpause_EmitsEvent() public {
        vm.prank(admin);
        syncPool.pause();

        vm.expectEmit(false, false, false, false, address(syncPool));
        emit Unpaused();
        vm.prank(admin);
        syncPool.unpause();
    }

    function test_Pause_RevertsWhenAlreadyPaused() public {
        vm.startPrank(admin);
        syncPool.pause();
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__AlreadyPaused.selector);
        syncPool.pause();
        vm.stopPrank();
    }

    function test_Unpause_RevertsWhenNotPaused() public {
        vm.prank(admin);
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__NotPaused.selector);
        syncPool.unpause();
    }

    function test_Pause_Unpause_Cycle() public {
        vm.prank(admin);
        syncPool.pause();
        vm.prank(admin);
        syncPool.unpause();
        vm.prank(admin);
        syncPool.pause();
        vm.prank(admin);
        syncPool.unpause();
    }

    // -----------------------------------------------------------------
    // Deposit hooks: pause guard
    // -----------------------------------------------------------------

    function test_AnticipatedDeposit_RevertsWhenPaused() public {
        vm.prank(admin);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__Paused.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_FinalizeDeposit_RevertsWhenPaused() public {
        vm.prank(admin);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__Paused.selector);
        syncPool.exposed_finalizeDeposit{value: 1 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    /// @dev After unpausing, the pause guard no longer trips; execution falls through
    /// to the next validation (`UnsetDummyToken` since no dummy token is registered).
    function test_AnticipatedDeposit_AfterUnpause_PassesPauseGuard() public {
        vm.prank(admin);
        syncPool.pause();
        vm.prank(admin);
        syncPool.unpause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_FinalizeDeposit_AfterUnpause_PassesPauseGuard() public {
        vm.prank(admin);
        syncPool.pause();
        vm.prank(admin);
        syncPool.unpause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_finalizeDeposit{value: 1 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    /// @dev Default state after `initialize`: deposit hooks are NOT paused.
    function test_Default_NotPaused() public {
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    // -----------------------------------------------------------------
    // PausableUntil: state transitions + events
    // -----------------------------------------------------------------

    function test_PauseUntil_SetsPausedUntilToTimestampPlusDuration() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        assertEq(syncPool.exposed_pausedUntil(), block.timestamp + syncPool.MAX_PAUSE_DURATION());
    }

    function test_PauseUntil_RecordsLastPauseTimestampForCaller() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        assertEq(syncPool.exposed_lastPauseTimestamp(address(this)), block.timestamp);
    }

    function test_PauseUntil_EmitsEvent() public {
        vm.warp(1_000_000);
        uint256 expectedUntil = block.timestamp + syncPool.MAX_PAUSE_DURATION();
        vm.expectEmit(false, false, false, true, address(syncPool));
        emit PausedUntil(expectedUntil);
        syncPool.exposed_pauseUntil();
    }

    function test_PauseUntil_RevertsWhenAlreadyPausedUntil() public {
        syncPool.exposed_pauseUntil();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();

        // Re-pause from a fresh caller so the cooldown branch isn't hit first;
        // the `_requireNotPausedUntil` check fires before the cooldown check.
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, pausedUntil)
        );
        syncPool.exposed_pauseUntil();
    }

    function test_UnpauseUntil_ResetsPausedUntilToZero() public {
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();
        assertEq(syncPool.exposed_pausedUntil(), 0);
    }

    function test_UnpauseUntil_EmitsEvent() public {
        syncPool.exposed_pauseUntil();
        vm.expectEmit(false, false, false, false, address(syncPool));
        emit UnpausedUntil();
        syncPool.exposed_unpauseUntil();
    }

    function test_UnpauseUntil_RevertsWhenNotPausedUntil() public {
        vm.expectRevert(PausableUntil.ContractNotPausedUntil.selector);
        syncPool.exposed_unpauseUntil();
    }

    function test_UnpauseUntil_DoesNotResetCallerCooldown() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        uint256 pauseTs = block.timestamp;
        syncPool.exposed_unpauseUntil();
        // lastPauseTimestamp is sticky — unpausing doesn't clear it.
        assertEq(syncPool.exposed_lastPauseTimestamp(address(this)), pauseTs);
    }

    // -----------------------------------------------------------------
    // PausableUntil: cooldown
    // -----------------------------------------------------------------

    function test_PauseUntil_RevertsDuringCooldown_SameCaller() public {
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();

        vm.expectRevert(PausableUntil.PauserCooldownStillActive.selector);
        syncPool.exposed_pauseUntil();
    }

    function test_PauseUntil_SucceedsAtCooldownBoundary_SameCaller() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();

        // Cooldown ends at `lastPauseTimestamp + pauseUntilDuration + PAUSER_UNTIL_COOLDOWN`.
        // The guard uses `>` (strict), so the exact boundary is allowed.
        uint256 cooldownEnd =
            syncPool.exposed_lastPauseTimestamp(address(this)) +
            syncPool.MAX_PAUSE_DURATION() +
            syncPool.PAUSER_UNTIL_COOLDOWN();
        vm.warp(cooldownEnd);

        syncPool.exposed_pauseUntil();
    }

    function test_PauseUntil_RevertsOneSecondBeforeCooldownBoundary_SameCaller() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();

        uint256 cooldownEnd =
            syncPool.exposed_lastPauseTimestamp(address(this)) +
            syncPool.MAX_PAUSE_DURATION() +
            syncPool.PAUSER_UNTIL_COOLDOWN();
        vm.warp(cooldownEnd - 1);

        vm.expectRevert(PausableUntil.PauserCooldownStillActive.selector);
        syncPool.exposed_pauseUntil();
    }

    function test_PauseUntil_AfterAutoExpiry_StillBlockedByCooldownForSameCaller() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();

        // Move past pausedUntil so `_requireNotPausedUntil` passes, but the
        // caller cooldown (pauseUntilDuration + PAUSER_UNTIL_COOLDOWN) is still active.
        vm.warp(block.timestamp + syncPool.MAX_PAUSE_DURATION() + 1);

        vm.expectRevert(PausableUntil.PauserCooldownStillActive.selector);
        syncPool.exposed_pauseUntil();
    }

    function test_PauseUntil_DifferentCallersHaveIndependentCooldowns() public {
        address callerA = makeAddr("pauseUntilCallerA");
        address callerB = makeAddr("pauseUntilCallerB");

        vm.prank(callerA);
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();

        // callerB has never paused, so the cooldown check passes for them.
        vm.prank(callerB);
        syncPool.exposed_pauseUntil();
        assertEq(syncPool.exposed_lastPauseTimestamp(callerB), block.timestamp);
    }

    // -----------------------------------------------------------------
    // PausableUntil: auto-expiry boundary on `_requireNotPausedUntil`
    // -----------------------------------------------------------------

    function test_PausedUntil_StillPausedAtExactBoundary() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();

        // Guard is `pausedUntil >= block.timestamp` → still paused at exact expiry.
        vm.warp(pausedUntil);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, pausedUntil)
        );
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_PausedUntil_AutoUnpausesOneSecondAfterBoundary() public {
        vm.warp(1_000_000);
        syncPool.exposed_pauseUntil();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();

        vm.warp(pausedUntil + 1);
        // Pause guard passes; falls through to next validation.
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    // -----------------------------------------------------------------
    // PausableUntil: deposit-hook pause guard
    // -----------------------------------------------------------------

    function test_AnticipatedDeposit_RevertsWhenPausedUntil() public {
        syncPool.exposed_pauseUntil();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();

        vm.expectRevert(
            abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, pausedUntil)
        );
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_FinalizeDeposit_RevertsWhenPausedUntil() public {
        syncPool.exposed_pauseUntil();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();

        vm.expectRevert(
            abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, pausedUntil)
        );
        syncPool.exposed_finalizeDeposit{value: 1 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_AnticipatedDeposit_AfterUnpauseUntil_PassesPauseGuard() public {
        syncPool.exposed_pauseUntil();
        syncPool.exposed_unpauseUntil();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    // -----------------------------------------------------------------
    // PausableUntil + global `_paused` are independent
    // -----------------------------------------------------------------

    function test_GlobalPausedAndPausedUntil_AreIndependent_GlobalCheckedFirst() public {
        // Set both pauses.
        vm.prank(admin);
        syncPool.pause();
        syncPool.exposed_pauseUntil();

        // Both active: `_requireNotPaused` is checked before `_requireNotPausedUntil`,
        // so the global pause error surfaces first.
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__Paused.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);

        // Lift the global pause; the pausedUntil guard still trips.
        vm.prank(admin);
        syncPool.unpause();
        uint256 pausedUntil = syncPool.exposed_pausedUntil();
        vm.expectRevert(
            abi.encodeWithSelector(PausableUntil.ContractPausedUntil.selector, pausedUntil)
        );
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_PausedUntilSet_DoesNotAffectGlobalPauseFlag() public {
        syncPool.exposed_pauseUntil();

        // Global `pause()` should still succeed; the two flags are tracked separately.
        vm.prank(admin);
        syncPool.pause();
    }

    // -----------------------------------------------------------------
    // PausableUntil: duration configuration
    // -----------------------------------------------------------------

    function test_SetPauseUntilDuration_UpdatesStorageAndEmitsEvent() public {
        uint256 newDuration = 1 days;
        vm.expectEmit(false, false, false, true, address(syncPool));
        emit PauseUntilDurationSet(newDuration);
        syncPool.exposed_setPauseUntilDuration(newDuration);
        assertEq(syncPool.pauseUntilDuration(), newDuration);
    }

    function test_SetPauseUntilDuration_RevertsBelowMin() public {
        // Resolve the constant before `vm.expectRevert` — it applies to the next external call.
        uint256 belowMin = syncPool.MIN_PAUSE_DURATION() - 1;
        vm.expectRevert(PausableUntil.InvalidPauseUntilDuration.selector);
        syncPool.exposed_setPauseUntilDuration(belowMin);
    }

    function test_SetPauseUntilDuration_RevertsAboveMax() public {
        uint256 aboveMax = syncPool.MAX_PAUSE_DURATION() + 1;
        vm.expectRevert(PausableUntil.InvalidPauseUntilDuration.selector);
        syncPool.exposed_setPauseUntilDuration(aboveMax);
    }

    function test_SetPauseUntilDuration_AllowsBoundaries() public {
        syncPool.exposed_setPauseUntilDuration(syncPool.MIN_PAUSE_DURATION());
        assertEq(syncPool.pauseUntilDuration(), syncPool.MIN_PAUSE_DURATION());

        syncPool.exposed_setPauseUntilDuration(syncPool.MAX_PAUSE_DURATION());
        assertEq(syncPool.pauseUntilDuration(), syncPool.MAX_PAUSE_DURATION());
    }

    // -----------------------------------------------------------------
    // PausableUntil: constants
    // -----------------------------------------------------------------

    function test_MinPauseDuration_Is8Hours() public {
        assertEq(syncPool.MIN_PAUSE_DURATION(), 8 hours);
    }

    function test_MaxPauseDuration_Is3Days() public {
        assertEq(syncPool.MAX_PAUSE_DURATION(), 3 days);
    }

    function test_PauserUntilCooldown_Is1Day() public {
        assertEq(syncPool.PAUSER_UNTIL_COOLDOWN(), 1 days);
    }
}
