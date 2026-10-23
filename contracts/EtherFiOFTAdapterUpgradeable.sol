// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTAdapterUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTAdapterUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OFTControls} from "./OFTControls.sol";

contract EtherfiOFTAdapterUpgradeable is OFTAdapterUpgradeable, AccessControlUpgradeable, PausableUpgradeable, OFTControls {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");
    bytes32 public constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");
    bytes32 public constant PAUSER_UNTIL_ROLE = keccak256("PAUSER_UNTIL_ROLE");

    /**
     * @dev Constructor for EtherfiOFTAdapterUpgradeable
     * @param _token The address of the already deployed weETH token 
     * @param _lzEndpoint The LZ endpoint address
     */
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param _owner The contract owner
     * @param _delegate The LZ delegate
     */
    function initialize(address _owner, address _delegate) external virtual reinitializer(2) {
        __Ownable_init(_owner);
        __OFTAdapter_init(_delegate);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
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
        if (amountSentLD > amountReceivedLD) innerToken.safeTransfer(feeDeposit(), amountSentLD - amountReceivedLD);
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
     * @dev Overrides the role admin logic from AccessControlUpgradeable to restrict granting roles to the owner
     */
    function grantRole(bytes32 role, address account) public override onlyOwner() {
        _grantRole(role, account);
    }

    /**
     * @dev Overrides the role admin logic from AccessControlUpgradeable to restrict revoking roles to the owner
     */
    function revokeRole(bytes32 role, address account) public override onlyOwner() {
        _revokeRole(role, account);
    }

    function _checkControlOwner() internal view virtual override {
        _checkOwner();
    }

    function _checkControlRole(ControlRole role) internal view virtual override {
        if (role == ControlRole.PAUSER) _checkRole(PAUSER_ROLE);
        else if (role == ControlRole.UNPAUSER) _checkRole(UNPAUSER_ROLE);
        else if (role == ControlRole.PAUSER_UNTIL) _checkRole(PAUSER_UNTIL_ROLE);
        else if (role == ControlRole.BLACKLISTER) _checkRole(BLACKLISTER_ROLE);
        else _checkRole(WHITELISTER_ROLE);
    }
}
