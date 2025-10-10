// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimpleEndpointMock
 * @dev A minimal mock endpoint for testing purposes
 * Only implements the functions needed for EtherfiOFTUpgradeable initialization
 */
contract SimpleEndpointMock {
    uint32 public immutable eid;
    
    constructor(uint32 _eid) {
        eid = _eid;
    }
    
    // Allow delegate setting for initialization
    function setDelegate(address) external {
        // Mock implementation - does nothing
    }
}
