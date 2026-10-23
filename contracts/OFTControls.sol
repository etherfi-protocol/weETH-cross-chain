// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AllowlistBaseUpgradeable} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/allowlist/AllowlistBaseUpgradeable.sol";
import {FeeConfigBaseUpgradeable} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/fee-config/FeeConfigBaseUpgradeable.sol";
import {FeeHandlerBaseUpgradeable} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/fee-accounting/FeeHandlerBaseUpgradeable.sol";
import {PairwiseRateLimiter} from "./PairwiseRateLimiter.sol";
import {PausableUntil} from "./PausableUntil.sol";

/**
 * @title OFT controls
 * @dev Additive controls shared by the weETH L2 OFT and the L1 adapter. Every control is off by default,
 * so an upgrade changes no behavior until governance turns a control on:
 * - Time-bound pause that expires on its own, for guardian use.
 * - Per-lane pause (one peer chain) next to the existing global pause.
 * - Blacklist and whitelist modes (LayerZero allowlist module). Mode defaults to Open.
 * - Bridge fee in bps with a hard cap, default and per lane (LayerZero fee config and fee handler modules).
 * - Credit redirect: bridged tokens for a blocked recipient go to an escrow, so the LayerZero message
 *   still executes instead of getting stuck. The escrow is one address in namespaced storage. The LayerZero
 *   credit redirect module is not used: it adds an external allowlist lookup that this contract's own
 *   allowlist makes redundant, and that costs about 560 bytes of the 24,576 byte size limit.
 * All new state lives in namespaced (ERC-7201) storage. The only sequential slots stay the two
 * PairwiseRateLimiter mappings.
 */
abstract contract OFTControls is
    PairwiseRateLimiter,
    PausableUntil,
    AllowlistBaseUpgradeable,
    FeeConfigBaseUpgradeable,
    FeeHandlerBaseUpgradeable
{
    /// @dev Roles the controls need. Each concrete contract maps these to its own role system.
    enum ControlRole {
        PAUSER,
        UNPAUSER,
        PAUSER_UNTIL,
        BLACKLISTER,
        WHITELISTER
    }

    /// @notice Highest bridge fee governance can set (1%).
    uint16 public constant MAX_FEE_BPS = 100;

    /// @custom:storage-location erc7201:etherfi.storage.OFTControls.LanePause
    struct LanePauseStorage {
        mapping(uint32 eid => bool paused) paused;
    }

    // keccak256(abi.encode(uint256(keccak256("etherfi.storage.OFTControls.LanePause")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LANE_PAUSE_STORAGE_LOCATION =
        0xf5e07c24aa97361d9e28da9bb4acbbff4c757b8632cfb9a116efef5271709000;

    /// @custom:storage-location erc7201:etherfi.storage.OFTControls.Escrow
    struct EscrowStorage {
        address escrow;
    }

    // keccak256(abi.encode(uint256(keccak256("etherfi.storage.OFTControls.Escrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ESCROW_STORAGE_LOCATION =
        0xf2658147a7b10195249e4f8aa0b3228ff5a4c05adc743b486607e14ef4c5fb00;

    event LanePauseSet(uint32 indexed eid, bool paused);
    event EscrowSet(address indexed escrow);
    /// @dev Same signature as the LayerZero ICreditRedirect event.
    event CreditRedirected(address indexed from, address indexed to, uint256 amountLD);

    error LanePaused(uint32 eid);
    error EscrowNotSet();
    error FeeDepositNotSet();
    error FeeTooHigh(uint16 feeBps);
    error PauseUntilDurationNotSet();

    /// @dev Reverts unless the caller is the contract owner.
    function _checkControlOwner() internal view virtual;

    /// @dev Reverts unless the caller holds `role` in the concrete contract's role system.
    function _checkControlRole(ControlRole role) internal view virtual;

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

    /// @notice Pauses a lane with the PAUSER role, unpauses it with the UNPAUSER role.
    function setLanePaused(uint32 eid, bool paused) external {
        _checkControlRole(paused ? ControlRole.PAUSER : ControlRole.UNPAUSER);
        _getLanePauseStorage().paused[eid] = paused;
        emit LanePauseSet(eid, paused);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowlist (blacklist / whitelist) and credit redirect
    // ---------------------------------------------------------------------------------------------

    function setAllowlistMode(AllowlistMode _mode) external {
        _checkControlOwner();
        if (_mode != AllowlistMode.Open && escrow() == address(0)) revert EscrowNotSet();
        _setAllowlistMode(_mode);
    }

    function setBlacklisted(SetAllowlistParam[] calldata _params) external {
        _checkControlRole(ControlRole.BLACKLISTER);
        _setBlacklisted(_params);
    }

    function setWhitelisted(SetAllowlistParam[] calldata _params) external {
        _checkControlRole(ControlRole.WHITELISTER);
        _setWhitelisted(_params);
    }

    function escrow() public view returns (address) {
        return _getEscrowStorage().escrow;
    }

    /// @notice Sets where bridged tokens go when the recipient is blocked. It cannot be cleared while the
    /// allowlist is enforced.
    function setEscrow(address _escrow) external {
        _checkControlOwner();
        if (_escrow == address(0) && allowlistMode() != AllowlistMode.Open) revert EscrowNotSet();
        _getEscrowStorage().escrow = _escrow;
        emit EscrowSet(_escrow);
    }

    // ---------------------------------------------------------------------------------------------
    // Fee
    // ---------------------------------------------------------------------------------------------

    function setFeeDeposit(address _feeDeposit) external {
        _checkControlOwner();
        _setFeeDeposit(_feeDeposit);
    }

    function setDefaultFeeBps(uint16 _feeBps) external {
        _checkControlOwner();
        _checkFeeBps(_feeBps);
        _setDefaultFeeBps(_feeBps);
    }

    /// @notice Sets the fee for one lane, keyed by peer endpoint id. A disabled entry falls back to the default.
    function setFeeBps(uint256 _id, uint16 _feeBps, bool _enabled) external {
        _checkControlOwner();
        _checkFeeBps(_feeBps);
        _setFeeBps(_id, _feeBps, _enabled);
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

    /// @dev Where `_amountLD` for `_to` should go: `_to` itself, or the escrow when `_to` is blocked.
    function _redirectCredit(address _to, uint256 _amountLD) internal returns (address) {
        if (isAllowlisted(_to)) return _to;
        address escrow_ = escrow();
        emit CreditRedirected(_to, escrow_, _amountLD);
        return escrow_;
    }

    // ---------------------------------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------------------------------

    function _getEscrowStorage() private pure returns (EscrowStorage storage $) {
        assembly {
            $.slot := ESCROW_STORAGE_LOCATION
        }
    }

    function _getLanePauseStorage() private pure returns (LanePauseStorage storage $) {
        assembly {
            $.slot := LANE_PAUSE_STORAGE_LOCATION
        }
    }

    function _checkFeeBps(uint16 _feeBps) private view {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps);
        if (_feeBps != 0 && feeDeposit() == address(0)) revert FeeDepositNotSet();
    }
}
