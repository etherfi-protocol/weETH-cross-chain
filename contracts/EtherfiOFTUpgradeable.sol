// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";

import {OFTUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTUpgradeable.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {PairwiseRateLimiter} from "./PairwiseRateLimiter.sol";

/**
 * @title Etherfi mintable upgradeable OFT token
 * @dev Extends MintableOFTUpgradeable with pausing and rate limiting functionality
 */
contract EtherfiOFTUpgradeable is OFTUpgradeable, PausableUpgradeable, PairwiseRateLimiter, IMintableERC20, EnumerableRoles {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Returns the maximum allowed role value
    /// @dev This is used by EnumerableRoles._validateRole to ensure roles are within valid range
    /// @return uint256 The maximum role value
    function MAX_ROLE() public pure returns (uint256) {
        return type(uint256).max;
    }

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
        __Pausable_init();
    }

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkAndUpdateOutboundRateLimit(_dstEid, _amountLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        _checkAndUpdateInboundRateLimit(_srcEid, _amountLD);
        return super._credit(_to, _amountLD, _srcEid);
    }

    /**
     * @notice Mint function that can only be called by a minter
     * @dev Used by the SyncPool contract in the native minting flow
     * @param _account The account to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external {
        if (!hasRole(_account, uint256(MINTER_ROLE))) revert EnumerableRolesUnauthorized();
        _mint(_account, _amount);
    }
    
    function setOutboundRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner() {
        _setOutboundRateLimits(_rateLimitConfigs);
    }

    function setInboundRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner() {
        _setInboundRateLimits(_rateLimitConfigs);
    }


   function pauseBridge() public {
        if (!hasRole(msg.sender, uint256(PAUSER_ROLE))) revert EnumerableRolesUnauthorized();
        _pause();
    }

    function unpauseBridge() external {
        if (!hasRole(msg.sender, uint256(UNPAUSER_ROLE))) revert EnumerableRolesUnauthorized();
        _unpause();
    }

    /**
     * @dev Grants a role to an account (only callable by owner)
     * @param role The role to grant (as bytes32)
     * @param account The address to grant the role to
     */
    function grantRole(bytes32 role, address account) public onlyOwner() {
        setRole(account, uint256(role), true);
    }

    /**
     * @dev Revokes a role from an account (only callable by owner)
     * @param role The role to revoke (as bytes32)
     * @param account The address to revoke the role from
     */
    function revokeRole(bytes32 role, address account) public onlyOwner() {
        setRole(account, uint256(role), false);
    }

    /**
     * @notice Gets all addresses that have a specific role
     * @param role The role to query (as bytes32)
     * @return address[] Array of addresses that have the specified role
     */
    function roleHolders(bytes32 role) public view returns (address[] memory) {
        return roleHolders(uint256(role));
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
