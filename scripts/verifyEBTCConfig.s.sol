// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../contracts/EtherfiOFTUpgradeable.sol";

import "forge-std/Script.sol";
import "../utils/LayerZeroHelpers.sol";

import "forge-std/Test.sol";

struct ConfigPerChain {
    string NAME;
    string RPC_URL;

    uint32 EID;
    address ENDPOINT;
    address SEND_302;
    address RECEIVE_302;
    address LAYERZERO_DVN;
    address NETHERMIND_DVN;
}

contract eBTCVerifier is Script, LayerZeroHelpers, Test {

    ConfigPerChain[] chains;
    constructor() {
        chains.push(CORN);
        chains.push(BASE);
        chains.push(ARB);
        chains.push(ETH);
    }

    function run() public {
        for (uint i = 0; i < chains.length; i++) {
            ConfigPerChain memory chain = chains[i];
            verifyChain(chain);
        }
    }

    // forge script scripts/verifyEBTCConfig.s.sol
    function verifyChain(ConfigPerChain memory chain) private {
        vm.createSelectFork(chain.RPC_URL);
        
        // all of the functions we would like to test are defined in the EtherfiOFTUpgradeable contract
        EtherfiOFTUpgradeable LayerZeroTeller = EtherfiOFTUpgradeable(LAYER_ZERO_TELLER);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(chain.ENDPOINT);

        console.log("Starting verifications of configurations on:", chain.NAME);
        console.log("====================================");   

        for (uint i = 0; i < chains.length; i++) {


            ConfigPerChain memory peerChain = chains[i];
            if (keccak256(abi.encodePacked(chain.NAME)) == keccak256(abi.encodePacked(peerChain.NAME))) {
                continue;
            }
            console.log("Verifying configurations for peer:", peerChain.NAME);
            
            assertEq(endpoint.getConfig(LAYER_ZERO_TELLER, chain.SEND_302, peerChain.EID, 2), _getExpectedUln(chain.LAYERZERO_DVN, chain.NETHERMIND_DVN), "Send config not set correctly");
            assertEq(endpoint.getConfig(LAYER_ZERO_TELLER, chain.RECEIVE_302, peerChain.EID, 2), _getExpectedUln(chain.LAYERZERO_DVN, chain.NETHERMIND_DVN), "Receive config not set correctly");

            bytes32 peerContract = LayerZeroTeller.peers(peerChain.EID);
            assertEq(peerContract, _toBytes32(LAYER_ZERO_TELLER), "Peer contract not set correctly");

            (,,uint256 limit, uint256 window) = LayerZeroTeller.outboundRateLimits(peerChain.EID);
            assertEq(limit, LIMIT, "Limit not set correctly for peer");
            assertEq(window, WINDOW, "Window not set correctly peer");

            (,,limit, window) = LayerZeroTeller.inboundRateLimits(peerChain.EID);
            assertEq(limit, LIMIT, "Limit not set correctly peer");
            assertEq(window, WINDOW, "Window not set correctly peer");
        }

        console.log("====================================\n");   
    }

    /**
    * CONSTANTS
    */

    // 20 bitcoins
    uint256 constant LIMIT = 2000000000;
    uint256 constant WINDOW = 4 hours;

    address constant LAYER_ZERO_TELLER = 0x6Ee3aaCcf9f2321E49063C4F8da775DdBd407268;

    ConfigPerChain CORN = ConfigPerChain({
        NAME: "corn",
        RPC_URL: "https://mainnet.corn-rpc.com",

        EID: 30331,
        ENDPOINT: 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa,
        SEND_302: 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043,
        RECEIVE_302: 0x2367325334447C5E1E0f1b3a6fB947b262F58312,

        LAYERZERO_DVN: 0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842,
        NETHERMIND_DVN: 0xE33de1A8cf9bcdC6b509C44EEF66f47c65dA6d47
    });

    ConfigPerChain BASE = ConfigPerChain({
        NAME: "base",
        RPC_URL: "https://base-mainnet.public.blastapi.io",

        EID: 30184,
        ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
        RECEIVE_302: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,

        LAYERZERO_DVN: 0x9e059a54699a285714207b43B055483E78FAac25, 
        NETHERMIND_DVN: 0xcd37CA043f8479064e10635020c65FfC005d36f6
    });

    ConfigPerChain ETH = ConfigPerChain({
        NAME: "ethereum",
        RPC_URL: "https://mainnet.gateway.tenderly.co",

        EID: 30101,
        ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
        RECEIVE_302: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,

        LAYERZERO_DVN: 0x589dEDbD617e0CBcB916A9223F4d1300c294236b, 
        NETHERMIND_DVN: 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5
    });

    ConfigPerChain ARB = ConfigPerChain({
        NAME: "arbitrum",
        RPC_URL: "https://arb1.arbitrum.io/rpc",

        EID: 30110,
        ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
        RECEIVE_302: 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6,

        LAYERZERO_DVN: 0x2f55C492897526677C5B68fb199ea31E2c126416, 
        NETHERMIND_DVN: 0xa7b5189bcA84Cd304D8553977c7C614329750d99
    });
}
