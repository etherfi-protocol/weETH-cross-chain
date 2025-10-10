// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/src/auth/EnumerableRoles.sol";

import {OFTUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTUpgradeable.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {PairwiseRateLimiter} from "./PairwiseRateLimiter.sol";

/**
 * @title Etherfi mintable upgradeable OFT token
 * @dev Extends MintableOFTUpgradeable with pausing and rate limiting functionality
 */
contract EtherfiOFTUpgradeable is OFTUpgradeable, EnumerableRoles, PausableUpgradeable, PairwiseRateLimiter, IMintableERC20 {
    uint256 public constant MINTER_ROLE = 1;
    uint256 public constant PAUSER_ROLE = 2;
    uint256 public constant UNPAUSER_ROLE = 3;

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

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkAndUpdateOutboundRateLimit(_dstEid, _amountLD);
        return super._debit(_amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        _checkAndUpdateInboundRateLimit(_srcEid, _amountLD);
        return super._credit(_to, _amountLD, 0);
    }

    /**
     * @notice Mint function that can only be called by a minter
     * @dev Used by the SyncPool contract in the native minting flow
     * @param _account The account to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_account, _amount);
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
