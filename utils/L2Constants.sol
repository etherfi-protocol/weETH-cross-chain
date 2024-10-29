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
        address LZ_EXECUTOR;
        address[2] LZ_DVN;

        // Addresses related to OFT deployment
        address L2_OFT;
        address L2_CONTRACT_CONTROLLER_SAFE;
        address L2_OFT_PROXY_ADMIN;

        // Addresses for the addition contracts required for native minting 
        address L2_SYNC_POOL;
        address L2_SYNC_POOL_RATE_LIMITER;
        address L2_EXCHANGE_RATE_PROVIDER;
        address L2_PRICE_ORACLE;
        address L2_MESSENGER;

        address L1_MESSENGER;
        address L1_DUMMY_TOKEN;
        address L1_RECEIVER;

        address L2_SYNC_POOL_PROXY_ADMIN;
        address L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN;
        address L1_DUMMY_TOKEN_PROXY_ADMIN;
        address L1_RECEIVER_PROXY_ADMIN;
    }

contract L2Constants {

    /*//////////////////////////////////////////////////////////////
                        OFT Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    // General chain constants
    string constant DEPLOYMENT_RPC_URL = "";
    string constant DEPLOYMENT_CHAIN_ID = "";
    
    // LayerZero addresses
    uint32 constant DEPLOYMENT_EID = 0;
    address constant DEPLOYMENT_SEND_LID_302 = address(0);
    address constant DEPLOYMENT_RECEIVE_LIB_302 = address(0);
    address constant DEPLOYMENT_LZ_DVN = address(0);
    address constant DEPLOYMENT_NETHERMIND_DVN = address(0);
    address constant DEPLOYMENT_LZ_ENDPOINT = address(0);

    // OFT deployment addresses
    address constant DEPLOYMENT_OFT = address(0);
    address constant DEPLOYMENT_CONTRACT_CONTROLLER = address(0);
    address constant DEPLOYMENT_PROXY_ADMIN_CONTRACT = address(0);

    /*//////////////////////////////////////////////////////////////
                    
    //////////////////////////////////////////////////////////////*/

    address constant DEPLOYER_ADDRESS = 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150;
    
    // OFT Token Constants
    string constant TOKEN_NAME = "Wrapped eETH";
    string constant TOKEN_SYMBOL = "weETH";
    
    // weETH Bridge Rate Limits
    uint256 constant BUCKET_SIZE = 3600000000000000000000;
    uint256 constant BUCKET_REFILL_PER_SECOND = 1000000000000000000;

    // Global Production weETH Bridge Rate Limits
    uint256 constant LIMIT = 2000 ether;
    uint256 constant WINDOW = 4 hours;
    // Global Stand By weETH Bridge Rate Limits
    uint256 constant STANDBY_LIMIT = 0.0001 ether;
    uint256 constant STANDBY_WINDOW = 1 minutes;

    // Standard Native Minting Rates
    uint32 constant L2_PRICE_ORACLE_HEART_BEAT = 24 hours;

    // Mainnet Constants
    string constant L1_RPC_URL = "https://gateway.tenderly.co/public/sepolia";
    uint32 constant L1_EID = 40161;
    address constant L1_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant L1_WEETH = address(0);
    address constant L1_CONTRACT_CONTROLLER = address(0);
    address constant L1_TIMELOCK_GNOSIS = address(0);
    address constant L1_TIMELOCK = address(0);

    address constant L1_SYNC_POOL = address(0);
    address constant L1_OFT_ADAPTER = address(0);
    address constant L1_VAMP = address(0);
    address constant L1_SEND_302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    address constant L1_RECEIVE_302 = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;
    address constant L1_LZ_DVN = 0x8eebf8b423b73bfca51a1db4b7354aa0bfca9193;
    address constant L1_NETHERMIND_DVN = 0xac294c43d44d4131db389256959f33e713851e31;
    address[2] L1_DVN = [0x8eebf8b423b73bfca51a1db4b7354aa0bfca9193, 0xac294c43d44d4131db389256959f33e713851e31];

    // https://docs.layerzero.network/v2/developers/solana/configuration/oapp-config#dead-dvn
    address constant DEAD_DVN = 0x000000000000000000000000000000000000dEaD;

    address constant L1_OFT_ADAPTER_PROXY_ADMIN = address(0);
    address constant L1_SYNC_POOL_PROXY_ADMIN = address(0);

    // Construct an array of all the L2s that are currently supported
    ConfigPerL2[] L2s;
    constructor () {
        L2s.push(BLAST);
        L2s.push(MODE);
        L2s.push(BNB);
        L2s.push(BASE);
        L2s.push(OP);
        L2s.push(SCROLL);
        L2s.push(LINEA);
        L2s.push(ZKSYNC);
    }

    ConfigPerL2 BLAST = ConfigPerL2({
        NAME: "blast",
        RPC_URL: "https://rpc.blast.io",
        CHAIN_ID: "81457",
        
        L2_EID: 30243,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821,
        RECEIVE_302: 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6,
        LZ_EXECUTOR: 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b,
        LZ_DVN: [0xc097ab8CD7b053326DFe9fB3E3a31a0CCe3B526f, 0xDd7B5E1dB4AaFd5C8EC3b764eFB8ed265Aa5445B],

        L2_OFT: 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
        L2_CONTRACT_CONTROLLER_SAFE: 0xa4822d7d24747e6A1BAA171944585bad4434f2D5,
        L2_OFT_PROXY_ADMIN: 0x2F6f3cc4a275C7951FB79199F01eD82421eDFb68,

        L2_SYNC_POOL: 0x52c4221Cb805479954CDE5accfF8C4DcaF96623B,
        L2_SYNC_POOL_RATE_LIMITER: 0x6f257089bF046a02751b60767871953F3899652e,
        L2_EXCHANGE_RATE_PROVIDER: 0xc42853c0C6624F42fcB8219aCeb67Ad188087DCB,
        L2_PRICE_ORACLE: 0xcD96262Df56127f298b452FA40759632868A472a,
        L2_MESSENGER: 0x4200000000000000000000000000000000000007,

        L1_MESSENGER: 0x5D4472f31Bd9385709ec61305AFc749F0fA8e9d0,
        L1_DUMMY_TOKEN: 0x83998e169026136760bE6AF93e776C2F352D4b28,
        L1_RECEIVER: 0x27e120C518a339c3d8b665E56c4503DF785985c2,

        L2_SYNC_POOL_PROXY_ADMIN: 0x8f732e00d6CF2302775Df16d4110f0f7ad3780f9,
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: 0xb4224E552016ba5D35b44608Cd4578fF7FCB6e82,
        L1_DUMMY_TOKEN_PROXY_ADMIN: 0x96a226ad7c14870502f9794fB481EE102E595fFa,
        L1_RECEIVER_PROXY_ADMIN: 0x70F38913d95987829577788dF9a6A0741dA16543
    });

    ConfigPerL2 MODE = ConfigPerL2({
        NAME: "mode",
        RPC_URL: "https://mainnet.mode.network",
        CHAIN_ID: "34443",

        L2_EID: 30260,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x2367325334447C5E1E0f1b3a6fB947b262F58312,
        RECEIVE_302: 0xc1B621b18187F74c8F6D52a6F709Dd2780C09821,
        LZ_EXECUTOR: 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b,
        LZ_DVN: [0xcd37CA043f8479064e10635020c65FfC005d36f6, 0xce8358bc28dd8296Ce8cAF1CD2b44787abd65887],

        L2_OFT: 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
        L2_CONTRACT_CONTROLLER_SAFE: 0xa4822d7d24747e6A1BAA171944585bad4434f2D5,
        L2_OFT_PROXY_ADMIN: 0x2F6f3cc4a275C7951FB79199F01eD82421eDFb68,

        L2_SYNC_POOL: 0x52c4221Cb805479954CDE5accfF8C4DcaF96623B,
        L2_SYNC_POOL_RATE_LIMITER: 0x95F1138837F1158726003251B32ecd8732c76781,
        L2_EXCHANGE_RATE_PROVIDER: 0xc42853c0C6624F42fcB8219aCeb67Ad188087DCB,
        L2_PRICE_ORACLE: 0x7C1DAAE7BB0688C9bfE3A918A4224041c7177256,
        L2_MESSENGER: 0xC0d3c0d3c0D3c0D3C0d3C0D3C0D3c0d3c0d30007,

        L1_MESSENGER: 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f,
        L1_DUMMY_TOKEN: 0xDc400f3da3ea5Df0B7B6C127aE2e54CE55644CF3,
        L1_RECEIVER: 0xC8Ad0949f33F02730cFf3b96E7F067E83De1696f,

        L2_SYNC_POOL_PROXY_ADMIN: 0x8f732e00d6CF2302775Df16d4110f0f7ad3780f9,
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: 0xb4224E552016ba5D35b44608Cd4578fF7FCB6e82,
        L1_DUMMY_TOKEN_PROXY_ADMIN: 0x59a5518aCE8e3d60C740503639B94bD86F7CEDF0,
        L1_RECEIVER_PROXY_ADMIN: 0xe85e493d78a4444bf5fC4A2E415AF530aEad6dd5
    });

    ConfigPerL2 LINEA = ConfigPerL2({
        NAME: "linea",
        RPC_URL: "https://linea-mainnet.public.blastapi.io",
        CHAIN_ID: "59144",

        L2_EID: 30183,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x32042142DD551b4EbE17B6FEd53131dd4b4eEa06,
        RECEIVE_302: 0xE22ED54177CE1148C557de74E4873619e6c6b205,
        LZ_EXECUTOR: 0x0408804C5dcD9796F22558464E6fE5bDdF16A7c7,
        LZ_DVN: [0x129Ee430Cb2Ff2708CCADDBDb408a88Fe4FFd480, 0xDd7B5E1dB4AaFd5C8EC3b764eFB8ed265Aa5445B],

        L2_OFT: 0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6,
        L2_CONTRACT_CONTROLLER_SAFE: 0xe4ff196Cd755566845D3dEBB1e2bD34123807eBc,
        L2_OFT_PROXY_ADMIN: 0xE21B7A5e4c15156180a76F4747313a3485fC4163,

        L2_SYNC_POOL: 0x823106E745A62D0C2FC4d27644c62aDE946D9CCa,
        L2_SYNC_POOL_RATE_LIMITER: 0x3A19866D5E0fAE0Ce19Adda617f9d2B9fD5a3975,
        L2_EXCHANGE_RATE_PROVIDER: 0x241a91F095B2020890Bc8518bea168C195518344,
        L2_PRICE_ORACLE: 0x100c8e61aB3BeA812A42976199Fc3daFbcDD7272,
        L2_MESSENGER: 0x508Ca82Df566dCD1B0DE8296e70a96332cD644ec,

        L1_MESSENGER: 0xd19d4B5d358258f05D7B411E21A1460D11B0876F,
        L1_DUMMY_TOKEN: 0x61Ff310aC15a517A846DA08ac9f9abf2A0f9A2bf,
        L1_RECEIVER: 0x6F149F8bf1CB0245e70171c9972059C22294aa35,

        L2_SYNC_POOL_PROXY_ADMIN: 0x0F88DB75B9011B909b67c498cdcc1C0FD2308444,
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: 0x40B6a79A93f9596Fe6155c9a56f79482d831178f,
        L1_DUMMY_TOKEN_PROXY_ADMIN: 0xaa249a01a3D73611a27B735130Ab77fd6b0f5a3e,
        L1_RECEIVER_PROXY_ADMIN: 0x7c6261c2eD0Bd5e532B45C4E553e633cBF34063f
    });


    ConfigPerL2 BASE = ConfigPerL2({
        NAME: "base",
        RPC_URL: "https://base-mainnet.public.blastapi.io",
        CHAIN_ID: "8453",

        L2_EID: 30184,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
        RECEIVE_302: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
        LZ_EXECUTOR: 0x1C90a7bAaB63CE90595effC31C06c9F5bE78a915,
        LZ_DVN: [0x9e059a54699a285714207b43B055483E78FAac25, 0xcd37CA043f8479064e10635020c65FfC005d36f6],

        L2_OFT: 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
        L2_CONTRACT_CONTROLLER_SAFE: 0x7a00657a45420044bc526B90Ad667aFfaee0A868,
        L2_OFT_PROXY_ADMIN: 0x2F6f3cc4a275C7951FB79199F01eD82421eDFb68,

        L2_SYNC_POOL: 0xc38e046dFDAdf15f7F56853674242888301208a5,
        L2_SYNC_POOL_RATE_LIMITER: 0xe6e0fe0C3Ac45d1FE71AF7853007467eE89e1e67,
        L2_EXCHANGE_RATE_PROVIDER: 0xF2c5519c634796B73dE90c7Dc27B4fEd560fC3ca,
        L2_PRICE_ORACLE: 0x35e9D7001819Ea3B39Da906aE6b06A62cfe2c181,
        L2_MESSENGER: 0x4200000000000000000000000000000000000007,

        L1_MESSENGER: 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa,
        L1_DUMMY_TOKEN: 0x0295E0CE709723FB25A28b8f67C54a488BA5aE46,
        L1_RECEIVER: 0x8963C96186bd05995AdaA9E1fda25B7181CCBc37,

        L2_SYNC_POOL_PROXY_ADMIN: 0x9055c6EF7Cb895D550368fE7B38Be346E7eA9eE6,
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: 0x7Ce9B21e86778Bb6D06CF107f1C154cB5635598f,
        L1_DUMMY_TOKEN_PROXY_ADMIN: 0x915B16B555872A084B3512169b1F1dC089C3ca9A,
        L1_RECEIVER_PROXY_ADMIN: 0x0df531532cf25156b1fe91232F41B4c9AA514125
    });


    // OFT only deployments below

    ConfigPerL2 BNB = ConfigPerL2({
        NAME: "bnb",
        RPC_URL: "https://bsc-dataseed1.binance.org/",
        CHAIN_ID: "56",

        L2_EID: 30102,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x9F8C645f2D0b2159767Bd6E0839DE4BE49e823DE,
        RECEIVE_302: 0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1,
        LZ_EXECUTOR: 0x3ebD570ed38B1b3b4BC886999fcF507e9D584859,
        LZ_DVN: [0x31F748a368a893Bdb5aBB67ec95F232507601A73, 0xfD6865c841c2d64565562fCc7e05e619A30615f0],

        L2_OFT: 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
        L2_CONTRACT_CONTROLLER_SAFE: 0xD568c4D42147224a701A14468bEC9E9bccF571F5,
        L2_OFT_PROXY_ADMIN: 0x2F6f3cc4a275C7951FB79199F01eD82421eDFb68,

        L2_SYNC_POOL: address(0),
        L2_SYNC_POOL_RATE_LIMITER: address(0),
        L2_EXCHANGE_RATE_PROVIDER: address(0),
        L2_PRICE_ORACLE: address(0),
        L2_MESSENGER: address(0),

        L1_MESSENGER: address(0),
        L1_DUMMY_TOKEN: address(0),
        L1_RECEIVER: address(0),

        L2_SYNC_POOL_PROXY_ADMIN: address(0),
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: address(0),
        L1_DUMMY_TOKEN_PROXY_ADMIN: address(0),
        L1_RECEIVER_PROXY_ADMIN: address(0)
    });

    ConfigPerL2 OP = ConfigPerL2({
        NAME: "op",
        RPC_URL: "https://optimism-rpc.publicnode.com",
        CHAIN_ID: "10",

        L2_EID: 30111,
        L2_ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x1322871e4ab09Bc7f5717189434f97bBD9546e95,
        RECEIVE_302: 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063,
        LZ_EXECUTOR: 0x2D2ea0697bdbede3F01553D2Ae4B8d0c486B666e,
        LZ_DVN: [0x6A02D83e8d433304bba74EF1c427913958187142, 0xa7b5189bcA84Cd304D8553977c7C614329750d99],

        L2_OFT: 0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF,
        L2_CONTRACT_CONTROLLER_SAFE: 0x764682c769CcB119349d92f1B63ee1c03d6AECFf,
        L2_OFT_PROXY_ADMIN: 0x632304Edc891Afed1a7bDe9A40b19F1c393ad5F3,

        L2_SYNC_POOL: address(0),
        L2_SYNC_POOL_RATE_LIMITER: address(0),
        L2_EXCHANGE_RATE_PROVIDER: address(0),
        L2_PRICE_ORACLE: address(0),
        L2_MESSENGER: address(0),

        L1_MESSENGER: address(0),
        L1_DUMMY_TOKEN: address(0),
        L1_RECEIVER: address(0),

        L2_SYNC_POOL_PROXY_ADMIN: address(0),
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: address(0),
        L1_DUMMY_TOKEN_PROXY_ADMIN: address(0),
        L1_RECEIVER_PROXY_ADMIN: address(0)
    });


    ConfigPerL2 SCROLL = ConfigPerL2({
        NAME: "scroll sepolia",
        RPC_URL: "https://sepolia-rpc.scroll.io/",
        CHAIN_ID: "534351",

        L2_EID: 40170,
        L2_ENDPOINT: 0x6EDCE65403992e310A62460808c4b910D972f10f,
        SEND_302: 0x21f1C2B131557c3AebA918D590815c47Dc4F20aa,
        RECEIVE_302: 0xf2dB23f9eA1311E9ED44E742dbc4268de4dB0a88,
        LZ_EXECUTOR: 0xD0D47C34937DdbeBBe698267a6BbB1dacE51198D,
        LZ_DVN: [0xb186F85d0604FE58af2Ea33fE40244f5EEF7351B, 0xcA01DAa8e559Cb6a810ce7906eC2AeA39BDeccE4],

        L2_OFT: address(0),
        L2_CONTRACT_CONTROLLER_SAFE: address(0), // will have to use an EOA
        L2_OFT_PROXY_ADMIN: address(0),

        L2_SYNC_POOL: address(0),
        L2_SYNC_POOL_RATE_LIMITER: address(0),
        L2_EXCHANGE_RATE_PROVIDER: address(0),
        L2_PRICE_ORACLE: address(0) ,
        L2_MESSENGER: 0xBa50f5340FB9F3Bd074bD638c9BE13eCB36E603d,
        
        L1_MESSENGER: 0x50c7d3e7f7c656493D1D76aaa1a836CedfCBB16A,
        L1_DUMMY_TOKEN: address(0),
        L1_RECEIVER: addresss(0),

        L2_SYNC_POOL_PROXY_ADMIN: address(0),
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: address(0),
        L1_DUMMY_TOKEN_PROXY_ADMIN: address(0),
        L1_RECEIVER_PROXY_ADMIN: address(0)
    });

    ConfigPerL2 ZKSYNC = ConfigPerL2({
        NAME: "zksync",
        RPC_URL: "https://mainnet.era.zksync.io",
        CHAIN_ID: "324",

        L2_EID: 30165,
        L2_ENDPOINT: 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF,
        SEND_302: 0x07fD0e370B49919cA8dA0CE842B8177263c0E12c,
        RECEIVE_302: 0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1,
        LZ_EXECUTOR: 0x664e390e672A811c12091db8426cBb7d68D5D8A6,
        LZ_DVN: [0x620A9DF73D2F1015eA75aea1067227F9013f5C51, 0xb183c2b91cf76cAd13602b32ADa2Fd273f19009C],

        L2_OFT: 0xc1Fa6E2E8667d9bE0Ca938a54c7E0285E9Df924a,
        L2_CONTRACT_CONTROLLER_SAFE: 0x8b9836176900A8EE62Dbe98066976D6CE829C53e,
        L2_OFT_PROXY_ADMIN: 0x908245fAA919eD7cF69d3f9ab75ED0F30d91D301,

        L2_SYNC_POOL: address(0),
        L2_SYNC_POOL_RATE_LIMITER: address(0),
        L2_EXCHANGE_RATE_PROVIDER: address(0),
        L2_PRICE_ORACLE: address(0),
        L2_MESSENGER: address(0),

        L1_MESSENGER: address(0),
        L1_DUMMY_TOKEN: address(0),
        L1_RECEIVER: address(0),

        L2_SYNC_POOL_PROXY_ADMIN: address(0),
        L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN: address(0),
        L1_DUMMY_TOKEN_PROXY_ADMIN: address(0),
        L1_RECEIVER_PROXY_ADMIN: address(0)
    });
}
