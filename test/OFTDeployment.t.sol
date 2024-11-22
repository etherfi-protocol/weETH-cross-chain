// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../contracts/MintableOFTUpgradeable.sol";
import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";

import "forge-std/Test.sol";

contract OFTDeploymentTest is Test, L2Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;

    function testGnosisMainnet() public {
        console.log("Tesing peer transactions for mainnet");
        vm.createSelectFork(L1_RPC_URL);
        vm.deal(L1_CONTRACT_CONTROLLER, 100 ether);

        string memory json = vm.readFile("./output/mainnet.json");
        uint256 numTransactions = 4;
        for (uint256 i = 0; i < numTransactions; i++) {
            address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].to"));
            uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].data"));

            vm.prank(L1_CONTRACT_CONTROLLER);
            (bool success,) = address(to).call{value: value}(data);
            require(success, "Transaction failed");
        }

        console.log("Confirming that the OFT for mainnet has added the deployment as a peer");
        MintableOFTUpgradeable adapter = MintableOFTUpgradeable(L1_OFT_ADAPTER);
        assertTrue(adapter.isPeer(DEPLOYMENT_EID, _toBytes32(DEPLOYMENT_OFT)));
        assertEq(adapter.enforcedOptions(DEPLOYMENT_EID, 1), hex"000301001101000000000000000000000000000f4240");
        assertEq(adapter.enforcedOptions(DEPLOYMENT_EID, 2), hex"000301001101000000000000000000000000000f4240");

        console.log("Confirming that the layerzero endpoint for mainnet is properly configured");
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(L1_ENDPOINT);
        assertEq(endpoint.getConfig(L1_OFT_ADAPTER, L1_SEND_302, DEPLOYMENT_EID, 2), _getExpectedUln(L1_DVN[0], L1_DVN[1]));
        assertEq(endpoint.getConfig(L1_OFT_ADAPTER, L1_RECEIVE_302, DEPLOYMENT_EID, 2), _getExpectedUln(L1_DVN[0], L1_DVN[1]));

        _sendCrossChain(DEPLOYMENT_EID, L1_OFT_ADAPTER, 1 ether, false);
    }

    function testGnosisL2() public {
        for (uint i = 0; i < L2s.length; i++) {

            if ( L2s[i].L2_EID == 30165) {
                // zksync has a different execution environment and we can't simulate against it here
                continue;
            }

            console.log("Testing gnosis peer transactions for %s", L2s[i].NAME);
            string memory l2Name = L2s[i].NAME;
            vm.createSelectFork(L2s[i].RPC_URL);
            vm.deal(L2s[i].L2_CONTRACT_CONTROLLER_SAFE, 100 ether);

            string memory filePath = string.concat("./output/", l2Name, ".json");
            string memory json = vm.readFile(filePath);
            console.log("Executing transactions for %s", l2Name);
            uint256 numTransactions = 5;
            for (uint256 j = 0; j < numTransactions; j++) {
                address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(j)), "].to"));
                uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(j)), "].value"));
                bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(j)), "].data"));

                vm.prank(L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
                (bool success,) = address(to).call{value: value}(data);
                require(success, "Transaction failed");
            }

            console.log("Confirming that the OFT for %s has added the deployment as a peer", L2s[i].NAME);
            MintableOFTUpgradeable oft = MintableOFTUpgradeable(L2s[i].L2_OFT);
            assertTrue(oft.isPeer(DEPLOYMENT_EID, _toBytes32(DEPLOYMENT_OFT)));
            (,,uint256 limit, uint256 window) = oft.rateLimits(DEPLOYMENT_EID);
            assertEq(limit, 2000 ether);
            assertEq(window, 4 hours);
            assertEq(oft.enforcedOptions(DEPLOYMENT_EID, 1), hex"000301001101000000000000000000000000000f4240");
            assertEq(oft.enforcedOptions(DEPLOYMENT_EID, 2), hex"000301001101000000000000000000000000000f4240");

            console.log("Confirming that the layerzero endpoint for %s is properly configured", L2s[i].NAME);
            ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(L2s[i].L2_ENDPOINT);
            assertEq(endpoint.getConfig(L2s[i].L2_OFT, L2s[i].SEND_302, DEPLOYMENT_EID, 2), _getExpectedUln(L2s[i].LZ_DVN[0], L2s[i].LZ_DVN[1]));
            assertEq(endpoint.getConfig(L2s[i].L2_OFT, L2s[i].RECEIVE_302, DEPLOYMENT_EID, 2), _getExpectedUln(L2s[i].LZ_DVN[0], L2s[i].LZ_DVN[1]));

            _sendCrossChain(DEPLOYMENT_EID, L2s[i].L2_OFT, 1 ether, false);
        }
    }

    function testDeployedOFT() public {
        // Confirm that the deployment chain is properly configured

        vm.createSelectFork(DEPLOYMENT_RPC_URL);
        MintableOFTUpgradeable oft = MintableOFTUpgradeable(DEPLOYMENT_OFT);

        console.log("confirming that L2 -> L1 configuration is correct");
        assertTrue(oft.isPeer(L1_EID, _toBytes32(L1_OFT_ADAPTER)));
        (,,uint256 limit, uint256 window) = oft.rateLimits(L1_EID);
        // STANDBY rate limits
        assertEq(limit, 0.0001 ether);
        assertEq(window, 1 minutes);
        assertEq(oft.enforcedOptions(L1_EID, 1), hex"000301001101000000000000000000000000000f4240");
        assertEq(oft.enforcedOptions(L1_EID, 2), hex"000301001101000000000000000000000000000f4240");

        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT);
        assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_SEND_LID_302, L1_EID, 2), _getExpectedUln(DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN));
        assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, L1_EID, 2), _getExpectedUln(DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN));

        for (uint i = 0; i < L2s.length; i++) {
            console.log("confirming that deployment -> %s configuration is correct", L2s[i].NAME);
            assertTrue(oft.isPeer(L2s[i].L2_EID, _toBytes32(L2s[i].L2_OFT)));
            (,,limit, window) = oft.rateLimits(L2s[i].L2_EID);
            // STANDBY rate limits
            assertEq(limit, 0.0001 ether);
            assertEq(window, 1 minutes);
            assertEq(oft.enforcedOptions(L2s[i].L2_EID, 1), hex"000301001101000000000000000000000000000f4240"); 
            assertEq(oft.enforcedOptions(L2s[i].L2_EID, 2), hex"000301001101000000000000000000000000000f4240");


            assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_SEND_LID_302, L2s[i].L2_EID, 2), _getExpectedUln(DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN));
            assertEq(endpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, L2s[i].L2_EID, 2), _getExpectedUln(DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN));
        }

        console.log("Testing successful cross chains");
        _sendCrossChain(L1_EID, DEPLOYMENT_OFT, 0.000001 ether, false);
        for (uint i = 0; i < L2s.length; i++) {
            _sendCrossChain(L2s[i].L2_EID, DEPLOYMENT_OFT, 0.000001 ether, false);
        }

        console.log("Testing failed sends do to rate limit increase");
        _sendCrossChain(L1_EID, DEPLOYMENT_OFT, 1 ether, true);
        for (uint i = 0; i < L2s.length; i++) {
            _sendCrossChain(L2s[i].L2_EID, DEPLOYMENT_OFT, 1 ether, true);
        }

        console.log("Executing transaction to increase rate limits");
        string memory json = vm.readFile("./output/productionRateLimit.json");
        uint256 numTransactions = 1;
        for (uint256 i = 0; i < numTransactions; i++) {
            address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].to"));
            uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].data"));

            vm.prank(DEPLOYMENT_CONTRACT_CONTROLLER);
            (bool success,) = address(to).call{value: value}(data);
            require(success, "Transaction failed");
        }

        console.log("Testing successful cross chain sends after rate limit increase");
        (,,limit, window) = oft.rateLimits(L1_EID);
        for (uint i = 0; i < L2s.length; i++) {
            (,,limit, window) = oft.rateLimits(L2s[i].L2_EID);
            // PROD rate limits
            assertEq(limit, 2000 ether);
            assertEq(window, 4 hours);
        }
        _sendCrossChain(L1_EID, DEPLOYMENT_OFT, 10 ether, false);
        for (uint i = 0; i < L2s.length; i++) {
            _sendCrossChain(L2s[i].L2_EID, DEPLOYMENT_OFT, 10 ether, false);
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
            to: _toBytes32(sender),
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
