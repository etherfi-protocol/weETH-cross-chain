// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";
import "../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../contracts/EtherFiOFTAdapter.sol";
import "../test/mock/MockMintToken.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";

/**
 * @title RoleTest
 * @dev Test suite demonstrating role enumerable functionality in EtherfiOFTUpgradeable and EtherfiOFTAdapterUpgradeable
 */
contract RoleTest is Test {
    // Mainnet constants
    string constant L1_RPC_URL = "https://mainnet.gateway.tenderly.co";
    address constant L1_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    
    // Test addresses
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public pauser = address(0x3);
    address public unpauser = address(0x4);
    
    // Mock weETH token for adapter
    MockMintableToken public mockWeETH;
    
    // Contract instances
    EtherfiOFTUpgradeable public oft;
    EtherfiOFTAdapterUpgradeable public adapter;
    EtherFiOFTAdapter public nonUpgradeableAdapter;
    
    // Role constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(L1_RPC_URL);
        
        // Deploy mock weETH token
        mockWeETH = new MockMintableToken("Mock weETH", "weETH");
        
        // Deploy contracts (without initialization to avoid the InvalidInitialization error)
        oft = new EtherfiOFTUpgradeable(L1_ENDPOINT);
        adapter = new EtherfiOFTAdapterUpgradeable(address(mockWeETH), L1_ENDPOINT);
        nonUpgradeableAdapter = new EtherFiOFTAdapter(address(mockWeETH), L1_ENDPOINT, owner);
        
        // Fund test addresses
        vm.deal(owner, 100 ether);
        vm.deal(minter, 100 ether);
        vm.deal(pauser, 100 ether);
        vm.deal(unpauser, 100 ether);
    }

    function testOFTRoleFunctionsExist() public view {
        // Test that role-related functions exist on the OFT contract
        uint256 maxRole = oft.MAX_ROLE();
        assertEq(maxRole, type(uint256).max);
        
        assertTrue(oft.MINTER_ROLE() == MINTER_ROLE);
        assertTrue(oft.PAUSER_ROLE() == PAUSER_ROLE);
        assertTrue(oft.UNPAUSER_ROLE() == UNPAUSER_ROLE);
    }

    // function testAdapterRoleFunctionsExist() public view {
    //     // Test that role-related functions exist on the Adapter contract
    //     uint256 maxRole = adapter.MAX_ROLE();
    //     assertEq(maxRole, type(uint256).max);
        
    //     assertTrue(adapter.PAUSER_ROLE() == PAUSER_ROLE);
    //     assertTrue(adapter.UNPAUSER_ROLE() == UNPAUSER_ROLE);
    // }

    // function testNonUpgradeableAdapter() public view {
    //     // Non-upgradeable adapter should not have role enumerable functionality
    //     assertEq(nonUpgradeableAdapter.owner(), owner);
    // }

    // function testRoleConstants() public view {
    //     // Test that role constants are properly defined
    //     assertEq(MINTER_ROLE, keccak256("MINTER_ROLE"));
    //     assertEq(PAUSER_ROLE, keccak256("PAUSER_ROLE"));
    //     assertEq(UNPAUSER_ROLE, keccak256("UNPAUSER_ROLE"));
        
    //     assertTrue(MINTER_ROLE != PAUSER_ROLE);
    //     assertTrue(MINTER_ROLE != UNPAUSER_ROLE);
    //     assertTrue(PAUSER_ROLE != UNPAUSER_ROLE);
    // }


}

