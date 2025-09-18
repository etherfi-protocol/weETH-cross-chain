// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OFTAdapterUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapterUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {PairwiseRateLimiter} from "./PairwiseRateLimiter.sol";

contract EtherfiOFTAdapterUpgradeable is OFTAdapterUpgradeable, PausableUpgradeable, PairwiseRateLimiter, EnumerableRoles {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Returns the maximum allowed role value
    /// @dev This is used by EnumerableRoles._validateRole to ensure roles are within valid range
    /// @return uint256 The maximum role value
    function MAX_ROLE() public pure returns (uint256) {
        return type(uint256).max;
    }

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
    function initialize(address _owner, address _delegate) external virtual initializer {
        __OFTAdapter_init(_delegate);
        __Pausable_init();
        _transferOwnership(_owner);
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
}
