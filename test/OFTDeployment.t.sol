// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../contracts/EtherfiOFTUpgradeable.sol";
import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";

import "forge-std/Test.sol";

contract OFTDeploymentTest is Test, L2Constants {
    using OptionsBuilder for bytes;

    /// Verifies the live config of the chain named by TARGET_CHAIN against the registry: peers,
    /// per-pathway rate limits, enforced options, and the 4-of-4 DVN set on both libraries. Then
    /// bridges within the limit, and proves a send above the limit reverts.
    ///
    /// Requires the chain's `peerEids`/`peerOfts`/`peerLimits`/`peerWindows` allow-list in
    /// registry/chains.json — that is the per-pathway policy this asserts. Chains that predate the
    /// allow-list are skipped rather than checked against a guessed expectation.
    function testDeployedOFT() public {
        if (bytes(DEPLOYMENT_RPC_URL).length == 0) {
            emit log_named_string("SKIP: no RPC for TARGET_CHAIN (set RPC_URL/RPC_ENV in the registry)", DEPLOYMENT_RPC_URL);
            vm.skip(true);
            return;
        }
        if (DEPLOYMENT_PEER_EIDS.length == 0) {
            emit log_string("SKIP: TARGET_CHAIN has no peerEids allow-list in registry/chains.json");
            vm.skip(true);
            return;
        }

        vm.createSelectFork(DEPLOYMENT_RPC_URL);
        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(DEPLOYMENT_OFT);

        console.log("testDeployedOFT: using registry peer allow-list (%d peers)", DEPLOYMENT_PEER_EIDS.length);

        address[4] memory dvns = DEPLOYMENT_DVNS;
        bytes memory expectedUln = LayerZeroHelpers._getExpectedUln4(dvns);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT);

        for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
            uint32 peerEid     = DEPLOYMENT_PEER_EIDS[i];
            address peerOft    = DEPLOYMENT_PEER_OFTS[i];
            uint256 peerLimit  = DEPLOYMENT_PEER_LIMITS[i];
            uint256 peerWindow = DEPLOYMENT_PEER_WINDOWS[i];

            console.log("confirming peer EID %d configuration is correct", peerEid);
            assertTrue(oft.isPeer(peerEid, LayerZeroHelpers._toBytes32(peerOft)));

            (,, uint256 inLimit, uint256 inWindow) = oft.inboundRateLimits(peerEid);
            assertEq(inLimit,  peerLimit);
            assertEq(inWindow, peerWindow);
            (,, uint256 outLimit, uint256 outWindow) = oft.outboundRateLimits(peerEid);
            assertEq(outLimit,  peerLimit);
            assertEq(outWindow, peerWindow);

            assertEq(oft.enforcedOptions(peerEid, 1), hex"00030100110100000000000000000000000000029810");
            assertEq(oft.enforcedOptions(peerEid, 2), hex"00030100110100000000000000000000000000029810");

            assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_SEND_LIB_302,    peerEid, 2), expectedUln);
            assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, peerEid, 2), expectedUln);
        }

        console.log("Testing successful cross-chain sends");
        for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
            _sendCrossChain(DEPLOYMENT_PEER_EIDS[i], DEPLOYMENT_OFT, 1 ether, false);
        }

        console.log("Testing rate-limit exceeded reverts");
        for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
            // Anything above the configured limit should revert.
            _sendCrossChain(DEPLOYMENT_PEER_EIDS[i], DEPLOYMENT_OFT, DEPLOYMENT_PEER_LIMITS[i] + 1 ether, true);
        }
    }

    // A helper function to send weETH cross chain
    function _sendCrossChain(uint32 dstEid, address oft, uint256 amount, bool expectRevert) public {
       // Generate address and fund with ETH and weETH
        address weETH = oft;
        if (block.chainid == 1) {
            weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        }
        address sender = vm.addr(1);
        vm.deal(sender, 100 ether);
        deal(address(weETH), address(sender), amount);

        vm.prank(sender);
        IERC20(weETH).approve(oft, amount);

        SendParam memory param = SendParam({
            dstEid: dstEid,
            to:LayerZeroHelpers._toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });

        IOFT oftInterface = IOFT(oft);
        MessagingFee memory fee = oftInterface.quoteSend(param, false);

        if (expectRevert) {
            // Expect to revert for rate limiting
            vm.expectRevert();
        }
        vm.prank(sender);
        oftInterface.send{value: fee.nativeFee}(
            param,
            fee,
            sender
        );
    }
}
