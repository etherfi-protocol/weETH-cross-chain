// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {CreditRedirectBaseUpgradeable} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/credit-redirect/CreditRedirectBaseUpgradeable.sol";
import {FeeHandlerBaseUpgradeable} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/fee-accounting/FeeHandlerBaseUpgradeable.sol";
import {PairwiseRateLimiter} from "./PairwiseRateLimiter.sol";
import {PausableUntil} from "./PausableUntil.sol";

/**
 * @title OFT controls
 * @dev Additive controls shared by the weETH L2 OFT and the L1 adapter. Every control is off by default,
 * so an upgrade changes no behavior until governance turns a control on:
 * - Time-bound pause that expires on its own, for guardian use.
 * - Per-lane pause (one peer chain) next to the existing global pause.
 * - Blacklist and whitelist modes, with the same enum, structs, events and errors as the LayerZero allowlist
 *   module. It uses plain mappings instead of that module's enumerable sets to keep the OFT under the
 *   24 KB contract size limit, so there are no on-chain list getters; read the events instead. Mode defaults
 *   to Open.
 * - One bridge fee in bps with a hard cap, paid to a fee deposit address (LayerZero fee handler module).
 *   The fee applies to every lane; the LayerZero per-lane fee config is left out to save contract size.
 * - Credit redirect: bridged tokens for a blocked recipient go to an escrow, so the LayerZero message
 *   still executes instead of getting stuck.
 * - Tighten-only rate limit changes for a manager role.
 * All new state lives in namespaced (ERC-7201) storage. The only sequential slots stay the two
 * PairwiseRateLimiter mappings.
 */
abstract contract OFTControls is
    PairwiseRateLimiter,
    PausableUntil,
    FeeHandlerBaseUpgradeable,
    CreditRedirectBaseUpgradeable
{
    /// @dev Roles the controls need. Each concrete contract maps these to its own role system.
    enum ControlRole {
        PAUSER,
        UNPAUSER,
        PAUSER_UNTIL,
        BLACKLISTER,
        WHITELISTER,
        RATE_LIMIT_MANAGER
    }

    /// @notice Highest bridge fee governance can set (1%).
    uint16 public constant MAX_FEE_BPS = 100;

    enum AllowlistMode {
        Open,
        Blacklist,
        Whitelist
    }

    struct SetAllowlistParam {
        address user;
        bool isEnabled;
    }

    /// @custom:storage-location erc7201:etherfi.storage.OFTControls.Allowlist
    struct AllowlistStorage {
        AllowlistMode mode;
        mapping(address user => bool blacklisted) blacklisted;
        mapping(address user => bool whitelisted) whitelisted;
    }

    // keccak256(abi.encode(uint256(keccak256("etherfi.storage.OFTControls.Allowlist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ALLOWLIST_STORAGE_LOCATION =
        0x65f04c6afe7b0d38b1d515c4e8141be1860627d15e40cdc3df2d372028aaa100;

    /// @custom:storage-location erc7201:etherfi.storage.OFTControls.Fee
    struct FeeStorage {
        uint16 feeBps;
    }

    // keccak256(abi.encode(uint256(keccak256("etherfi.storage.OFTControls.Fee")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEE_STORAGE_LOCATION =
        0x5c1a238c6547369c944e98340402a9a1e9f3c5b9ae8e4bb341dd8d21df2acb00;

    /// @custom:storage-location erc7201:etherfi.storage.OFTControls.LanePause
    struct LanePauseStorage {
        mapping(uint32 eid => bool paused) paused;
    }

    // keccak256(abi.encode(uint256(keccak256("etherfi.storage.OFTControls.LanePause")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LANE_PAUSE_STORAGE_LOCATION =
        0xf5e07c24aa97361d9e28da9bb4acbbff4c757b8632cfb9a116efef5271709000;

    event LanePauseSet(uint32 indexed eid, bool paused);
    event DefaultFeeBpsSet(uint16 feeBps);
    event AllowlistModeUpdated(AllowlistMode newMode);
    event BlacklistUpdated(address indexed user, bool isBlacklisted);
    event WhitelistUpdated(address indexed user, bool isWhitelisted);

    error LanePaused(uint32 eid);
    error ModeAlreadySet(AllowlistMode mode);
    error AllowlistStateIdempotent(address user, bool isEnabled);
    error NotAllowlisted(address user, AllowlistMode mode);
    error EscrowNotSet();
    error FeeDepositNotSet();
    error FeeTooHigh(uint16 feeBps);
    error RateLimitNotTightening(uint32 peerEid);
    error PauseUntilDurationNotSet();
    error UnauthorizedInitializer();

    /// @dev Reverts unless the caller is the contract owner.
    function _checkControlOwner() internal view virtual;

    /// @dev Reverts unless the caller holds `role` in the concrete contract's role system.
    function _checkControlRole(ControlRole role) internal view virtual;

    function __OFTControls_init(address feeDeposit_, uint256 pauseUntilDuration_) internal onlyInitializing {
        _setFeeDeposit(feeDeposit_);
        _setPauseUntilDuration(pauseUntilDuration_);
    }

    // ---------------------------------------------------------------------------------------------
    // Pause
    // ---------------------------------------------------------------------------------------------

    /**
     * @notice Pauses the bridge until `pauseUntilDuration` has passed. It unpauses itself, so a guardian key
     * can stop the bridge without being able to keep it stopped.
     */
    function pauseBridgeUntil() external {
        _checkControlRole(ControlRole.PAUSER_UNTIL);
        if (_getPausableUntilStorage().pauseUntilDuration == 0) revert PauseUntilDurationNotSet();
        _pauseUntil();
    }

    function unpauseBridgeUntil() external {
        _checkControlRole(ControlRole.UNPAUSER);
        _unpauseUntil();
    }

    function setPauseUntilDuration(uint256 pauseUntilDuration_) external {
        _checkControlOwner();
        _setPauseUntilDuration(pauseUntilDuration_);
    }

    function isLanePaused(uint32 eid) public view returns (bool) {
        return _getLanePauseStorage().paused[eid];
    }

    function pauseLanes(uint32[] calldata eids) external {
        _checkControlRole(ControlRole.PAUSER);
        _setLanesPaused(eids, true);
    }

    function unpauseLanes(uint32[] calldata eids) external {
        _checkControlRole(ControlRole.UNPAUSER);
        _setLanesPaused(eids, false);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowlist (blacklist / whitelist) and credit redirect
    // ---------------------------------------------------------------------------------------------

    function allowlistMode() public view returns (AllowlistMode) {
        return _getAllowlistStorage().mode;
    }

    function isBlacklisted(address _user) public view returns (bool) {
        return _getAllowlistStorage().blacklisted[_user];
    }

    function isWhitelisted(address _user) public view returns (bool) {
        return _getAllowlistStorage().whitelisted[_user];
    }

    function isAllowlisted(address _user) public view returns (bool) {
        AllowlistStorage storage $ = _getAllowlistStorage();
        if ($.mode == AllowlistMode.Open) return true;
        if ($.mode == AllowlistMode.Blacklist) return !$.blacklisted[_user];
        return $.whitelisted[_user];
    }

    function setAllowlistMode(AllowlistMode _mode) external {
        _checkControlOwner();
        AllowlistStorage storage $ = _getAllowlistStorage();
        if ($.mode == _mode) revert ModeAlreadySet(_mode);
        if (_mode != AllowlistMode.Open && creditRedirectConfig().escrow == address(0)) revert EscrowNotSet();
        $.mode = _mode;
        emit AllowlistModeUpdated(_mode);
    }

    function setBlacklisted(SetAllowlistParam[] calldata _params) external {
        _checkControlRole(ControlRole.BLACKLISTER);
        _updateAllowlist(_getAllowlistStorage().blacklisted, _params, true);
    }

    function setWhitelisted(SetAllowlistParam[] calldata _params) external {
        _checkControlRole(ControlRole.WHITELISTER);
        _updateAllowlist(_getAllowlistStorage().whitelisted, _params, false);
    }

    /**
     * @notice Sets where bridged tokens go when the recipient is blocked. `allowlist` must be this contract
     * (or zero together with `escrow`). The escrow cannot be cleared while the allowlist is enforced.
     */
    function setCreditRedirectConfig(CreditRedirectConfig calldata _config) external {
        _checkControlOwner();
        if (_config.escrow == address(0) && allowlistMode() != AllowlistMode.Open) revert EscrowNotSet();
        if (_config.allowlist != address(0) && _config.allowlist != address(this)) revert InvalidCreditRedirectConfig();
        _setCreditRedirectConfig(_config);
    }

    // ---------------------------------------------------------------------------------------------
    // Fee
    // ---------------------------------------------------------------------------------------------

    function setFeeDeposit(address _feeDeposit) external {
        _checkControlOwner();
        _setFeeDeposit(_feeDeposit);
    }

    function defaultFeeBps() public view returns (uint16) {
        return _getFeeStorage().feeBps;
    }

    /// @notice Fee taken from `_amount` when bridging to or from `_eid`. The fee is the same on every lane.
    function getFee(uint256, uint256 _amount) public view returns (uint256) {
        return (_amount * defaultFeeBps()) / 10_000;
    }

    function setDefaultFeeBps(uint16 _feeBps) external {
        _checkControlOwner();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps);
        if (_feeBps != 0 && feeDeposit() == address(0)) revert FeeDepositNotSet();
        _getFeeStorage().feeBps = _feeBps;
        emit DefaultFeeBpsSet(_feeBps);
    }

    // ---------------------------------------------------------------------------------------------
    // Rate limits: tighten-only for the manager role. The owner keeps the full setters.
    // ---------------------------------------------------------------------------------------------

    /// @notice Lowers limits only. Fails if a config raises the limit/window rate or enables a peer.
    function tightenRateLimits(RateLimitConfig[] calldata _rateLimitConfigs, bool _outbound) external {
        _checkControlRole(ControlRole.RATE_LIMIT_MANAGER);
        for (uint256 i = 0; i < _rateLimitConfigs.length; i++) {
            RateLimitConfig calldata config = _rateLimitConfigs[i];
            _requireTightening(_outbound ? outboundRateLimits[config.peerEid] : inboundRateLimits[config.peerEid], config);
        }
        if (_outbound) _setOutboundRateLimits(_rateLimitConfigs);
        else _setInboundRateLimits(_rateLimitConfigs);
    }

    // ---------------------------------------------------------------------------------------------
    // Hooks used by the concrete _debit / _credit / _debitView
    // ---------------------------------------------------------------------------------------------

    function _checkOutbound(uint32 _dstEid, address _sender) internal view {
        _requireNotPausedUntil();
        if (isLanePaused(_dstEid)) revert LanePaused(_dstEid);
        _requireAllowlisted(_sender);
    }

    function _checkInbound(uint32 _srcEid) internal view {
        _requireNotPausedUntil();
        if (isLanePaused(_srcEid)) revert LanePaused(_srcEid);
    }

    function _requireAllowlisted(address _user) internal view {
        if (!isAllowlisted(_user)) revert NotAllowlisted(_user, allowlistMode());
    }

    /// @dev Amount the destination receives. Fee and dust both come out of the sender's amount, so the
    /// source and destination balances stay 1:1 with no dust left behind.
    function _amountAfterFee(
        uint32 _dstEid,
        uint256 _amountSentLD,
        uint256 _dustUnit
    ) internal view returns (uint256 amountReceivedLD) {
        uint256 fee = getFee(_dstEid, _amountSentLD);
        if (fee == 0) return _amountSentLD;
        // forge-lint: disable-next-line(divide-before-multiply)
        return ((_amountSentLD - fee) / _dustUnit) * _dustUnit; // rounds down to the shared-decimals unit
    }

    /// @dev Credit redirect uses this contract's own allowlist, not an external one.
    function _isAllowlisted(address _user) internal view virtual override returns (bool) {
        return isAllowlisted(_user);
    }

    // ---------------------------------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------------------------------

    function _updateAllowlist(
        mapping(address user => bool listed) storage _list,
        SetAllowlistParam[] calldata _params,
        bool _blacklist
    ) private {
        for (uint256 i = 0; i < _params.length; i++) {
            SetAllowlistParam calldata param = _params[i];
            // forge-lint: disable-next-line(require-revert-in-loop)
            if (_list[param.user] == param.isEnabled) revert AllowlistStateIdempotent(param.user, param.isEnabled);
            _list[param.user] = param.isEnabled;
            if (_blacklist) emit BlacklistUpdated(param.user, param.isEnabled);
            else emit WhitelistUpdated(param.user, param.isEnabled);
        }
    }

    function _getAllowlistStorage() private pure returns (AllowlistStorage storage $) {
        assembly {
            $.slot := ALLOWLIST_STORAGE_LOCATION
        }
    }

    function _getLanePauseStorage() private pure returns (LanePauseStorage storage $) {
        assembly {
            $.slot := LANE_PAUSE_STORAGE_LOCATION
        }
    }

    function _setLanesPaused(uint32[] calldata _eids, bool _paused) private {
        LanePauseStorage storage $ = _getLanePauseStorage();
        for (uint256 i = 0; i < _eids.length; i++) {
            $.paused[_eids[i]] = _paused;
            emit LanePauseSet(_eids[i], _paused);
        }
    }

    function _getFeeStorage() private pure returns (FeeStorage storage $) {
        assembly {
            $.slot := FEE_STORAGE_LOCATION
        }
    }

    /// @dev New rate (limit / window) must not exceed the current rate. An unconfigured peer cannot be enabled.
    function _requireTightening(RateLimit storage _current, RateLimitConfig calldata _new) private view {
        if (_current.window == 0 || _new.window == 0 || _new.limit * _current.window > _current.limit * _new.window) {
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert RateLimitNotTightening(_new.peerEid);
        }
    }
}
