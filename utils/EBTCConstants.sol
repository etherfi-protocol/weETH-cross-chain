// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

    struct ConfigPerL2 {
        // General chain info
        string NAME;
        string RPC_URL;
        string CHAIN_ID;

        /**
        * constants and addresses related to sending LayerZero messages
        * https://docs.layerzero.network/v2/developers/evm/technical-reference/endpoints
        * https://docs.layerzero.network/v2/developers/evm/technical-reference/executor-addresses
        * https://docs.layerzero.network/v2/developers/evm/technical-reference/messagelibs
        * https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
        */
        uint32 L2_EID;
        address L2_ENDPOINT;
        address SEND_302;
        address RECEIVE_302;
        address[2] LZ_DVN;

        // Addresses related to OFT deployment
        address L2_OFT;
        address L2_CONTRACT_CONTROLLER_SAFE;
        address L2_OFT_PROXY_ADMIN;

    }

contract EBTCConstants {

    /*//////////////////////////////////////////////////////////////
                        CURRENT DEPLOYMENT CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // General chain constants
    string constant DEPLOYMENT_RPC_URL = "";
    string constant DEPLOYMENT_CHAIN_ID = "";
    
    // LayerZero addresses
    uint32 constant DEPLOYMENT_EID = 0;
    address constant DEPLOYMENT_LZ_ENDPOINT = address(0);
    address constant DEPLOYMENT_SEND_LID_302 = address(0);
    address constant DEPLOYMENT_RECEIVE_LIB_302 = address(0);
    address constant DEPLOYMENT_LZ_DVN = address(0);
    address[2] DEPLOYMENT_DVN = [address(0), address(0)];

    // OFT deployment addresses
    address constant DEPLOYMENT_OFT = address(0);
    address constant DEPLOYMENT_CONTRACT_CONTROLLER = address(0);
    address constant DEPLOYMENT_PROXY_ADMIN_CONTRACT = address(0);

    /*//////////////////////////////////////////////////////////////
                    
    //////////////////////////////////////////////////////////////*/

    address constant DEPLOYER_ADDRESS = 0x8d5aAC5d3D5cDa4c404Fa7eE13B0822B648bB150;
    
    // OFT Token Constants
    string constant TOKEN_NAME = "ether.fi BTC";
    string constant TOKEN_SYMBOL = "eBTC";

    // Global Production Rate Limits
    uint256 constant LIMIT = 3_000_000_000; // 30 BTC
    uint256 constant WINDOW = 4 hours;

    // Mainnet Constants
    string constant L1_RPC_URL = "https://mainnet.gateway.tenderly.co";
    address constant L1_CONTRACT_CONTROLLER = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC;
    address constant L1_TIMELOCK_GNOSIS = 0xcdd57D11476c22d265722F68390b036f3DA48c21;
    address constant L1_TIMELOCK = 0x9f26d4C958fD811A1F59B01B86Be7dFFc9d20761;

    address constant L1_OFT_ADAPTER = address(0x0);

    // LayerZero Mainnet Constants
    uint32 constant L1_EID = 30101;
    address constant L1_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant L1_SEND_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant L1_RECEIVE_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    address[2] L1_DVN = [0x589dEDbD617e0CBcB916A9223F4d1300c294236b, 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5];

    // https://docs.layerzero.network/v2/developers/solana/configuration/oapp-config#dead-dvn
    address constant DEAD_DVN = 0x000000000000000000000000000000000000dEaD;

    // Cross chain pauser EOA
    address constant PAUSER_EOA = 0x9AF1298993DC1f397973C62A5D47a284CF76844D;

    // Construct an array of all the L2s that are currently supported
    ConfigPerL2[] L2s;
    constructor () {
        
    }

    ConfigPerL2 BASE = ConfigPerL2({
        NAME: "base",
        RPC_URL: "https://base-mainnet.public.blastapi.io",
        CHAIN_ID: "8453",

        L2_EID: 30184,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
        RECEIVE_302: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
        LZ_DVN: [0x9e059a54699a285714207b43B055483E78FAac25, 0xcd37CA043f8479064e10635020c65FfC005d36f6],

        L2_OFT: address(0x0),
        L2_CONTRACT_CONTROLLER_SAFE: address(0x0),
        L2_OFT_PROXY_ADMIN: address(0x0)
    });

    ConfigPerL2 ARBITRUM = ConfigPerL2({
        NAME: "arbitrum",
        RPC_URL: "https://arb1.arbitrum.io/rpc",
        CHAIN_ID: "42161",

        L2_EID: 30110,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
        RECEIVE_302: 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6,
        LZ_DVN: [0x2f55C492897526677C5B68fb199ea31E2c126416, 0xa7b5189bcA84Cd304D8553977c7C614329750d99],

        L2_OFT: address(0x0),
        L2_CONTRACT_CONTROLLER_SAFE: address(0x0),
        L2_OFT_PROXY_ADMIN: address(0x0)
    });
    
    ConfigPerL2 SCROLL = ConfigPerL2({
        NAME: "scroll",
        RPC_URL: "https://scroll-mainnet.public.blastapi.io",
        CHAIN_ID: "534352",

        L2_EID: 30214,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B,
        RECEIVE_302: 0x8363302080e711E0CAb978C081b9e69308d49808,
        LZ_DVN: [0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2, 0x446755349101cB20c582C224462c3912d3584dCE],

        L2_OFT: address(0x0),
        L2_CONTRACT_CONTROLLER_SAFE: address(0x0),
        L2_OFT_PROXY_ADMIN: address(0x0)
    });
}
