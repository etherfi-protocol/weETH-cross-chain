// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRoleRegistry {
    bytes32 public constant UPGRADE_TIMELOCK_ROLE = keccak256("UPGRADE_TIMELOCK_ROLE");
    bytes32 public constant OPERATION_TIMELOCK_ROLE = keccak256("OPERATION_TIMELOCK_ROLE");
    bytes32 public constant OPERATION_MULTISIG_ROLE = keccak256("OPERATION_MULTISIG_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    mapping(bytes32 => mapping(address => bool)) public roles;
    address public owner;

    error Unauthorized();
    error OnlyOperatingTimelock();
    error OnlyOperatingMultisig();
    error OnlyGuardian();

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

    function onlyOperatingTimelock(address account) external view {
        if (!roles[OPERATION_TIMELOCK_ROLE][account]) revert OnlyOperatingTimelock();
    }

    function onlyOperatingMultisig(address account) external view {
        if (!roles[OPERATION_MULTISIG_ROLE][account]) revert OnlyOperatingMultisig();
    }

    function onlyGuardian(address account) external view {
        if (!roles[GUARDIAN_ROLE][account]) revert OnlyGuardian();
    }
}
