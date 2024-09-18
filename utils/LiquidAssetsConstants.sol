// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract LiquidConstants {

    /*//////////////////////////////////////////////////////////////
                        Mainnet Constants
    //////////////////////////////////////////////////////////////*/

    // LayerZero values
    uint32 constant L1_EID = 30101;
    address constant L1_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address[2] L1_DVN = [0x589dEDbD617e0CBcB916A9223F4d1300c294236b, 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5];
    address constant L1_SEND_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant L1_RECEIVE_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    // Etherfi values
    address constant L1_CONTRACT_CONTROLLER = 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B;
    address constant WEETHS = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    string constant WEETHS_NAME = "Super Symbiotic LRT";
    string constant WEETHS_SYMBOL = "weETHs";
    address constant WBTC = 0x657e8C867D8B37dCC18fA4Caead9C45EB088C642;
    string constant EBTC_NAME = "ether.fi BTC";
    string constant EBTC_SYMBOL = "eBTC";
    


    /*//////////////////////////////////////////////////////////////
                        Scroll Constants
    //////////////////////////////////////////////////////////////*/

    // LayerZero values
    uint32 constant SCROLL_EID = 30214;
    address constant SCROLL_LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address[2] SCROLL_DVN = [0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2, 0x446755349101cB20c582C224462c3912d3584dCE];
    address constant SCROLL_SEND_302 = 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B;
    address constant SCROLL_RECEIVE_302 = 0x8363302080e711E0CAb978C081b9e69308d49808;

    // Etherfi values
    address constant SCROLL_CONTRACT_CONTROLLER = 0x3cD08f51D0EA86ac93368DE31822117cd70CECA3;

}
