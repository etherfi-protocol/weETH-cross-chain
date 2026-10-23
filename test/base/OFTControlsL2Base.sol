// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {SendParam, OFTReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";

import {EtherfiOFTUpgradeable} from "../../contracts/EtherfiOFTUpgradeable.sol";
import {PairwiseRateLimiter} from "../../contracts/PairwiseRateLimiter.sol";
import {OFTEndpointMock} from "../mock/OFTEndpointMock.sol";

/// @dev Shared L2 token setup for the OFT controls tests: one lane, every role granted to its own address.
abstract contract OFTControlsL2Base is Test {
    uint32 constant PEER_EID = 30101;
    uint256 constant BLACKLISTER_ROLE = 4;
    uint256 constant WHITELISTER_ROLE = 5;
    uint256 constant PAUSER_UNTIL_ROLE = 6;
    uint256 constant LIMIT = 1_000_000 ether;
    uint256 constant WINDOW = 1 days;

    OFTEndpointMock endpoint;
    EtherfiOFTUpgradeable oft;

    address owner = makeAddr("owner");
    address minter = makeAddr("minter");
    address pauser = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address guardian = makeAddr("guardian");
    address blacklister = makeAddr("blacklister");
    address whitelister = makeAddr("whitelister");
    address feeDeposit = makeAddr("feeDeposit");
    address escrow = makeAddr("escrow");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    bytes32 peer = bytes32(uint256(uint160(makeAddr("peer"))));

    function setUp() public {
        vm.warp(1_800_000_000);
        endpoint = new OFTEndpointMock(30184);
        EtherfiOFTUpgradeable impl = new EtherfiOFTUpgradeable(address(endpoint));
        oft = EtherfiOFTUpgradeable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(EtherfiOFTUpgradeable.initialize, ("Wrapped eETH", "weETH", owner))
        )));

        PairwiseRateLimiter.RateLimitConfig[] memory limits = new PairwiseRateLimiter.RateLimitConfig[](1);
        limits[0] = PairwiseRateLimiter.RateLimitConfig(PEER_EID, LIMIT, WINDOW);

        vm.startPrank(owner);
        oft.setFeeDeposit(feeDeposit);
        oft.setPauseUntilDuration(1 days);
        oft.setPeer(PEER_EID, peer);
        oft.setOutboundRateLimits(limits);
        oft.setInboundRateLimits(limits);
        oft.setRole(minter, oft.MINTER_ROLE(), true);
        oft.setRole(pauser, oft.PAUSER_ROLE(), true);
        oft.setRole(unpauser, oft.UNPAUSER_ROLE(), true);
        oft.setRole(guardian, PAUSER_UNTIL_ROLE, true);
        oft.setRole(blacklister, BLACKLISTER_ROLE, true);
        oft.setRole(whitelister, WHITELISTER_ROLE, true);
        vm.stopPrank();

        vm.prank(minter);
        oft.mint(user, 1000 ether);
    }


    function _send(address from, uint256 amount, uint256 minAmount) internal returns (OFTReceipt memory receipt) {
        SendParam memory param = SendParam(PEER_EID, bytes32(uint256(uint160(from))), amount, minAmount, "", "", "");
        MessagingFee memory fee = oft.quoteSend(param, false);
        vm.deal(from, 1 ether);
        vm.prank(from);
        (, receipt) = oft.send{value: fee.nativeFee}(param, fee, from);
    }

    function _receive(address to, uint256 amountLD) internal {
        Origin memory origin = Origin(PEER_EID, peer, 1);
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(to))), uint64(amountLD / 1e12));
        vm.prank(address(endpoint));
        oft.lzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function _blacklist(address account) internal {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(account, true);
        vm.prank(blacklister);
        oft.setBlacklisted(params);
    }

    function _enableBlacklistMode() internal {
        vm.startPrank(owner);
        oft.setEscrow(escrow);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Blacklist);
        vm.stopPrank();
    }

    function sendExternal(address from, uint256 amount) external {
        _send(from, amount, 0);
    }

    function sendExternalWithMin(address from, uint256 amount, uint256 minAmount) external {
        _send(from, amount, minAmount);
    }

    function receiveExternal(address to, uint256 amount) external {
        _receive(to, amount);
    }
}
