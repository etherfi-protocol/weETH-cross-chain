// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRoleRegistry {
    bytes32 public constant PROTOCOL_PAUSER = keccak256("PROTOCOL_PAUSER");
    bytes32 public constant PROTOCOL_UNPAUSER = keccak256("PROTOCOL_UNPAUSER");

    mapping(bytes32 => mapping(address => bool)) public roles;
    address public owner;

    error Unauthorized();

    constructor(address _owner) {
        owner = _owner;
    }

    function grantRole(bytes32 role, address account) external {
        if (msg.sender != owner) revert Unauthorized();
        roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external {
        if (msg.sender != owner) revert Unauthorized();
        roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roles[role][account];
    }
}