// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EtherfiOFTUpgradeable} from "../contracts/EtherfiOFTUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {EnumerableRoles} from "lib/solady/src/auth/EnumerableRoles.sol";
import {EndpointV2Mock} from "lib/devtools/packages/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";

contract EtherfiOFTUpgradeableRolesTest is Test {

    EtherfiOFTUpgradeable public etherfiOFT;
    EndpointV2Mock public lzEndpoint;

    address public owner = makeAddr("owner");
    address public minter = makeAddr("minter");
    address public pauser = makeAddr("pauser");
    address public unpauser = makeAddr("unpauser");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    function setUp() public {
        lzEndpoint = new EndpointV2Mock(1, address(this));

        EtherfiOFTUpgradeable etherfiOFTImpl = new EtherfiOFTUpgradeable(address(lzEndpoint));
        etherfiOFT = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(etherfiOFTImpl),
            abi.encodeWithSelector(EtherfiOFTUpgradeable.initialize.selector, "EtherFi Token", "weETH", owner)
        )));

        vm.deal(user, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function test_RoleManagement() public {
        address[] memory initialMinters = etherfiOFT.roleHolders(etherfiOFT.MINTER_ROLE());
        address[] memory initialPausers = etherfiOFT.roleHolders(etherfiOFT.PAUSER_ROLE());
        address[] memory initialUnpausers = etherfiOFT.roleHolders(etherfiOFT.UNPAUSER_ROLE());

        assertEq(initialMinters.length, 0);
        assertEq(initialPausers.length, 0);
        assertEq(initialUnpausers.length, 0);

        assertFalse(etherfiOFT.hasRole(minter, etherfiOFT.MINTER_ROLE()));
        assertFalse(etherfiOFT.hasRole(pauser, etherfiOFT.PAUSER_ROLE()));
        assertFalse(etherfiOFT.hasRole(unpauser, etherfiOFT.UNPAUSER_ROLE()));

        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        etherfiOFT.setRole(unpauser, etherfiOFT.UNPAUSER_ROLE(), true);
        vm.stopPrank();

        assertTrue(etherfiOFT.hasRole(minter, etherfiOFT.MINTER_ROLE()));
        assertTrue(etherfiOFT.hasRole(pauser, etherfiOFT.PAUSER_ROLE()));
        assertTrue(etherfiOFT.hasRole(unpauser, etherfiOFT.UNPAUSER_ROLE()));

        address[] memory minters = etherfiOFT.roleHolders(etherfiOFT.MINTER_ROLE());
        address[] memory pausers = etherfiOFT.roleHolders(etherfiOFT.PAUSER_ROLE());
        address[] memory unpausers = etherfiOFT.roleHolders(etherfiOFT.UNPAUSER_ROLE());

        assertEq(minters.length, 1);
        assertEq(pausers.length, 1);
        assertEq(unpausers.length, 1);
        assertEq(minters[0], minter);
        assertEq(pausers[0], pauser);
        assertEq(unpausers[0], unpauser);
    }

    function test_RoleManagement_OnlyOwner() public {
        // Test that non-owner cannot set roles
        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.EnumerableRolesUnauthorized.selector));
        vm.prank(user);
        etherfiOFT.setRole(minter, 1, true);

        // Test that owner can set roles
        vm.startPrank(owner);
        etherfiOFT.setRole(minter, 1, true);
        vm.stopPrank();
        assertTrue(etherfiOFT.hasRole(minter, 1));

        vm.startPrank(owner);
        etherfiOFT.setRole(user, 1, true);
        vm.stopPrank();
        assertTrue(etherfiOFT.hasRole(user, 1));
    }

    function test_Mint_WithoutRole() public {
        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.EnumerableRolesUnauthorized.selector));
        etherfiOFT.mint(user, 1000 ether);
    }

    function test_Mint_WithRole() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        vm.stopPrank();

        uint256 balanceBefore = etherfiOFT.balanceOf(user);
        
        vm.prank(minter);
        etherfiOFT.mint(user, 1000 ether);

        assertEq(etherfiOFT.balanceOf(user), balanceBefore + 1000 ether);
    }

    function test_PauseBridge_WithoutRole() public {
        assertFalse(etherfiOFT.paused());

        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.EnumerableRolesUnauthorized.selector));
        etherfiOFT.pauseBridge();

        assertFalse(etherfiOFT.paused());
    }

    function test_PauseBridge_WithRole() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        vm.stopPrank();

        assertFalse(etherfiOFT.paused());

        vm.prank(pauser);
        etherfiOFT.pauseBridge();

        assertTrue(etherfiOFT.paused());
    }

    function test_UnpauseBridge_WithoutRole() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        vm.stopPrank();

        vm.prank(pauser);
        etherfiOFT.pauseBridge();
        assertTrue(etherfiOFT.paused());

        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.EnumerableRolesUnauthorized.selector));
        etherfiOFT.unpauseBridge();

        assertTrue(etherfiOFT.paused());
    }

    function test_UnpauseBridge_WithRole() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        etherfiOFT.setRole(unpauser, etherfiOFT.UNPAUSER_ROLE(), true);
        vm.stopPrank();

        vm.prank(pauser);
        etherfiOFT.pauseBridge();
        assertTrue(etherfiOFT.paused());

        vm.prank(unpauser);
        etherfiOFT.unpauseBridge();

        assertFalse(etherfiOFT.paused());
    }

    function test_RoleRevocation() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        vm.stopPrank();

        assertTrue(etherfiOFT.hasRole(minter, etherfiOFT.MINTER_ROLE()));

        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), false);
        vm.stopPrank();

        assertFalse(etherfiOFT.hasRole(minter, etherfiOFT.MINTER_ROLE()));

        address[] memory minters = etherfiOFT.roleHolders(etherfiOFT.MINTER_ROLE());
        assertEq(minters.length, 0);
    }

    function test_MultipleRoleHolders() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(user, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        etherfiOFT.setRole(user2, etherfiOFT.PAUSER_ROLE(), true);
        etherfiOFT.setRole(unpauser, etherfiOFT.UNPAUSER_ROLE(), true);
        vm.stopPrank();

        address[] memory minters = etherfiOFT.roleHolders(etherfiOFT.MINTER_ROLE());
        address[] memory pausers = etherfiOFT.roleHolders(etherfiOFT.PAUSER_ROLE());
        address[] memory unpausers = etherfiOFT.roleHolders(etherfiOFT.UNPAUSER_ROLE());

        assertEq(minters.length, 2);
        assertEq(pausers.length, 2);
        assertEq(unpausers.length, 1);

        // Test that both minters can mint
        vm.prank(minter);
        etherfiOFT.mint(user, 1000 ether);
        assertEq(etherfiOFT.balanceOf(user), 1000 ether);

        vm.prank(user);
        etherfiOFT.mint(user2, 500 ether);
        assertEq(etherfiOFT.balanceOf(user2), 500 ether);

        // Test that both pausers can pause
        vm.prank(pauser);
        etherfiOFT.pauseBridge();
        assertTrue(etherfiOFT.paused());

        vm.prank(unpauser);
        etherfiOFT.unpauseBridge();
        assertFalse(etherfiOFT.paused());

        vm.prank(user2);
        etherfiOFT.pauseBridge();
        assertTrue(etherfiOFT.paused());
    }

    function test_RoleHolderCount() public {
        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.MINTER_ROLE()), 0);
        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.PAUSER_ROLE()), 0);
        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.UNPAUSER_ROLE()), 0);

        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(user, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(pauser, etherfiOFT.PAUSER_ROLE(), true);
        vm.stopPrank();

        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.MINTER_ROLE()), 2);
        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.PAUSER_ROLE()), 1);
        assertEq(etherfiOFT.roleHolderCount(etherfiOFT.UNPAUSER_ROLE()), 0);
    }

    function test_RoleHolderAt() public {
        vm.startPrank(owner);
        etherfiOFT.setRole(minter, etherfiOFT.MINTER_ROLE(), true);
        etherfiOFT.setRole(user, etherfiOFT.MINTER_ROLE(), true);
        vm.stopPrank();

        address firstMinter = etherfiOFT.roleHolderAt(etherfiOFT.MINTER_ROLE(), 0);
        address secondMinter = etherfiOFT.roleHolderAt(etherfiOFT.MINTER_ROLE(), 1);

        // The order might vary, but both addresses should be present
        assertTrue(firstMinter == minter || firstMinter == user);
        assertTrue(secondMinter == minter || secondMinter == user);
        assertTrue(firstMinter != secondMinter);

        // Test out of bounds
        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.RoleHoldersIndexOutOfBounds.selector));
        etherfiOFT.roleHolderAt(1, 2);
    }

    function test_ZeroAddressRoleHolder() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(EnumerableRoles.RoleHolderIsZeroAddress.selector));
        etherfiOFT.setRole(address(0), 1, true);
        vm.stopPrank();
    }
}
