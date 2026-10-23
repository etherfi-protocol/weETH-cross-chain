// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/src/auth/EnumerableRoles.sol";
import {IFundRecovery} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IFundRecovery.sol";

import {OFTUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTUpgradeable.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {OFTControls} from "./OFTControls.sol";

/**
 * @title Etherfi mintable upgradeable OFT token
 * @dev Extends MintableOFTUpgradeable with pausing and rate limiting functionality.
 * OFTControls adds the time-bound pause, per-lane pause, allowlist, bridge fee and credit redirect.
 */
contract EtherfiOFTUpgradeable is OFTUpgradeable, EnumerableRoles, PausableUpgradeable, OFTControls, IMintableERC20, IFundRecovery {
    uint256 public constant MINTER_ROLE = 1;
    uint256 public constant PAUSER_ROLE = 2;
    uint256 public constant UNPAUSER_ROLE = 3;
    uint256 internal constant BLACKLISTER_ROLE = 4;
    uint256 internal constant WHITELISTER_ROLE = 5;
    uint256 internal constant PAUSER_UNTIL_ROLE = 6;

    event FundsRecovered(address indexed from, address indexed to, uint256 amount);

    error CannotRecoverFrom(address from);

    /**
     * @dev Constructor for MintableOFT
     * @param endpoint The layer zero endpoint address
     */
    constructor(address endpoint) OFTUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param owner The owner of the token
     */
    function initialize(string memory name, string memory symbol, address owner) external virtual initializer {
        __OFT_init(name, symbol, owner);
        __Ownable_init(owner);
    }

    function _debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal view virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        amountSentLD = _removeDust(_amountLD);
        amountReceivedLD = _amountAfterFee(_dstEid, amountSentLD, decimalConversionRate);
        if (amountReceivedLD < _minAmountLD) revert SlippageExceeded(amountReceivedLD, _minAmountLD);
    }

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkOutbound(_dstEid, msg.sender);
        _checkAndUpdateOutboundRateLimit(_dstEid, _amountLD);
        (amountSentLD, amountReceivedLD) = super._debit(_amountLD, _minAmountLD, _dstEid);
        if (amountSentLD > amountReceivedLD) _mint(feeDeposit(), amountSentLD - amountReceivedLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        _checkInbound(_srcEid);
        _checkAndUpdateInboundRateLimit(_srcEid, _amountLD);
        address recipient = _redirectCredit(_to, _amountLD);
        super._credit(recipient, _amountLD, 0);
        return recipient == _to ? _amountLD : 0;
    }

    /**
     * @notice Mint function that can only be called by a minter
     * @dev Used by the SyncPool contract in the native minting flow
     * @param _account The account to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _requireAllowlisted(_account);
        _mint(_account, _amount);
    }

    /// @dev Holder-to-holder transfers need both sides allowlisted. Mint and burn skip the check: the paths
    /// that mint or burn (`mint`, `_debit`, `_credit`) check the allowlist themselves.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) {
            _requireAllowlisted(from);
            _requireAllowlisted(to);
        }
        super._update(from, to, value);
    }

    /**
     * @notice Moves tokens out of a blacklisted address. Only works in Blacklist mode and only for an address
     * on the blacklist, so a mode change cannot expose other holders.
     */
    function recoverFunds(address _from, address _to, uint256 _amount) external onlyOwner() {
        if (allowlistMode() != AllowlistMode.Blacklist || !isBlacklisted(_from)) revert CannotRecoverFrom(_from);
        if (_to == address(0)) revert ERC20InvalidReceiver(address(0));
        // skips the allowlist check in this contract's _update, which would block a blacklisted sender
        ERC20Upgradeable._update(_from, _to, _amount);
        emit FundsRecovered(_from, _to, _amount);
    }
    
    function setOutboundRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner() {
        _setOutboundRateLimits(_rateLimitConfigs);
    }

    function setInboundRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner() {
        _setInboundRateLimits(_rateLimitConfigs);
    }


   function pauseBridge() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpauseBridge() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Sets the status of `role` of `holder` to `active`.
     * Only the owner can set roles.
     */
    function setRole(address holder, uint256 role, bool active) public payable override {
        if (msg.sender != owner()) revert EnumerableRolesUnauthorized();
        super._setRole(holder, role, active);
    }

    function _checkControlOwner() internal view virtual override {
        _checkOwner();
    }

    function _checkControlRole(ControlRole role) internal view virtual override {
        uint256 id;
        if (role == ControlRole.PAUSER) id = PAUSER_ROLE;
        else if (role == ControlRole.UNPAUSER) id = UNPAUSER_ROLE;
        else if (role == ControlRole.PAUSER_UNTIL) id = PAUSER_UNTIL_ROLE;
        else if (role == ControlRole.BLACKLISTER) id = BLACKLISTER_ROLE;
        else id = WHITELISTER_ROLE;
        if (!hasRole(msg.sender, id)) revert EnumerableRolesUnauthorized();
    }

    function updateTokenSymbol(string memory name_, string memory symbol_) external onlyOwner() {
        ERC20Storage storage $ = getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

    function getERC20Storage() internal pure returns (ERC20Storage storage $) {
        bytes32 ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        assembly {
            $.slot := ERC20StorageLocation
        }
    }
}
