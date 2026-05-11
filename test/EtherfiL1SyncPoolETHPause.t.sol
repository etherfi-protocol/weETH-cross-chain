// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EtherfiL1SyncPoolETH} from "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import {Constants} from "../contracts/libraries/Constants.sol";

import {SimpleEndpointMock} from "./mock/SimpleEndpointMock.sol";
import {MockRoleRegistry} from "./mock/MockRoleRegistry.sol";

/// @dev Exposes the internal deposit hooks so the pause guard can be exercised
/// directly without standing up the full LayerZero / liquifier dependency graph.
contract EtherfiL1SyncPoolETHHarness is EtherfiL1SyncPoolETH {
    constructor(address endpoint, address roleRegistry) EtherfiL1SyncPoolETH(endpoint, roleRegistry) {}

    function exposed_anticipatedDeposit(
        uint32 originEid,
        bytes32 guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256) {
        return _anticipatedDeposit(originEid, guid, tokenIn, amountIn, amountOut);
    }

    function exposed_finalizeDeposit(
        uint32 originEid,
        bytes32 guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) external payable {
        _finalizeDeposit(originEid, guid, tokenIn, amountIn, amountOut);
    }
}

contract EtherfiL1SyncPoolETHPauseTest is Test {
    EtherfiL1SyncPoolETHHarness internal syncPool;
    SimpleEndpointMock internal endpoint;
    MockRoleRegistry internal roleRegistry;

    address internal owner = makeAddr("owner");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal stranger = makeAddr("stranger");
    address internal liquifier = makeAddr("liquifier");
    address internal eEth = makeAddr("eEth");
    address internal tokenOut = makeAddr("tokenOut");
    address internal lockBox = makeAddr("lockBox");

    event Paused();
    event Unpaused();

    function setUp() public {
        endpoint = new SimpleEndpointMock(1);
        roleRegistry = new MockRoleRegistry(owner);

        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_PAUSER(), pauser);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_UNPAUSER(), unpauser);
        vm.stopPrank();

        EtherfiL1SyncPoolETHHarness impl = new EtherfiL1SyncPoolETHHarness(address(endpoint), address(roleRegistry));
        syncPool = EtherfiL1SyncPoolETHHarness(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(
                        EtherfiL1SyncPoolETH.initialize.selector,
                        liquifier,
                        eEth,
                        tokenOut,
                        lockBox,
                        owner
                    )
                )
            )
        );

        vm.deal(address(this), 100 ether);
    }

    // -----------------------------------------------------------------
    // Access control
    // -----------------------------------------------------------------

    function test_Pause_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EtherfiL1SyncPoolETH.IncorrectCaller.selector)
        );
        syncPool.pause();
    }

    function test_Unpause_OnlyOwner() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(EtherfiL1SyncPoolETH.IncorrectCaller.selector)
        );
        syncPool.unpause();
    }

    // -----------------------------------------------------------------
    // State transitions + events
    // -----------------------------------------------------------------

    function test_Pause_EmitsEvent() public {
        vm.expectEmit(false, false, false, false, address(syncPool));
        emit Paused();
        vm.prank(pauser);
        syncPool.pause();
    }

    function test_Unpause_EmitsEvent() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.expectEmit(false, false, false, false, address(syncPool));
        emit Unpaused();
        vm.prank(unpauser);
        syncPool.unpause();
    }

    function test_Pause_RevertsWhenAlreadyPaused() public {
        vm.startPrank(pauser);
        syncPool.pause();
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__AlreadyPaused.selector);
        syncPool.pause();
        vm.stopPrank();
    }

    function test_Unpause_RevertsWhenNotPaused() public {
        vm.prank(unpauser);
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__NotPaused.selector);
        syncPool.unpause();
    }

    function test_Pause_Unpause_Cycle() public {
        vm.prank(pauser);
        syncPool.pause();
        vm.prank(unpauser);
        syncPool.unpause();
        vm.prank(pauser);
        syncPool.pause();
        vm.prank(unpauser);
        syncPool.unpause();
    }

    // -----------------------------------------------------------------
    // Deposit hooks: pause guard
    // -----------------------------------------------------------------

    function test_AnticipatedDeposit_RevertsWhenPaused() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__Paused.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_FinalizeDeposit_RevertsWhenPaused() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__Paused.selector);
        syncPool.exposed_finalizeDeposit{value: 1 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    /// @dev `tokenIn != ETH` is checked before the pause flag, so a non-ETH deposit
    /// during pause must still surface as `OnlyETH`, not `Paused`.
    function test_AnticipatedDeposit_TokenInCheckBeforePauseCheck() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__OnlyETH.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), address(0xdead), 1 ether, 0);
    }

    /// @dev `amountIn != msg.value` is checked before the pause flag in `_finalizeDeposit`.
    function test_FinalizeDeposit_AmountMismatchBeforePauseCheck() public {
        vm.prank(pauser);
        syncPool.pause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__InvalidAmountIn.selector);
        syncPool.exposed_finalizeDeposit{value: 0.5 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    /// @dev After unpausing, the pause guard no longer trips; execution falls through
    /// to the next validation (`UnsetDummyToken` since no dummy token is registered).
    function test_AnticipatedDeposit_AfterUnpause_PassesPauseGuard() public {
        vm.prank(pauser);
        syncPool.pause();
        vm.prank(unpauser);
        syncPool.unpause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    function test_FinalizeDeposit_AfterUnpause_PassesPauseGuard() public {
        vm.prank(pauser);
        syncPool.pause();
        vm.prank(unpauser);
        syncPool.unpause();

        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_finalizeDeposit{value: 1 ether}(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }

    /// @dev Default state after `initialize`: deposit hooks are NOT paused.
    function test_Default_NotPaused() public {
        vm.expectRevert(EtherfiL1SyncPoolETH.EtherfiL1SyncPoolETH__UnsetDummyToken.selector);
        syncPool.exposed_anticipatedDeposit(1, bytes32(0), Constants.ETH_ADDRESS, 1 ether, 0);
    }
}
