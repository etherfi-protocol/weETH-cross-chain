// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "../../contracts/native-minting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/native-minting/l2-syncpools/HydraSyncPoolETHUpgradeable.sol";
import "../../contracts/native-minting/BucketRateLimiter.sol";

import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../../utils/GnosisHelpers.sol";
import "../../interfaces/ICreate3Deployer.sol";

// forge script scripts/native-minting-deployment/DeployConfigureL2.s.sol:L2NativeMintingScript --evm-version "shanghai" --via-ir --ledger --verify --slow --rpc-url "l2 rpc" --etherscan-api-key "chain api key"
contract L2NativeMintingScript is Script, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);


    // addition constants for hydra deployment
    // hydra deployed wETH on bera
    address constant HYDRA_WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // StargateOFTETH deployed on bera
    address constant STARGATE_OFT_ETH = 0x45f1A95A4D3f3836523F5c83673c797f4d4d263B;

    function deployConfigureExchangeRateProvider(address scriptDeployer) private returns (address) {
        address impl = CREATE3.deployCreate3(keccak256("ExchangeRateProviderImpl"), type(EtherfiL2ExchangeRateProvider).creationCode);

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, 
            abi.encode(impl, BERA.L2_CONTRACT_CONTROLLER_SAFE, abi.encodeWithSelector(EtherfiL2ExchangeRateProvider.initialize.selector, scriptDeployer))
        );
        address proxy = address(CREATE3.deployCreate3(keccak256("ExchangeRateProvider"), proxyCreationCode));
        console.log("Exchange Rate Provider deployed at: ", proxy);
        require(proxy == BERA.L2_EXCHANGE_RATE_PROVIDER, "Exchange Rate Provider address mismatch");
        
        EtherfiL2ExchangeRateProvider provider = EtherfiL2ExchangeRateProvider(proxy);
        provider.setRateParameters(HYDRA_WETH, BERA.L2_PRICE_ORACLE, 0, L2_PRICE_ORACLE_HEART_BEAT);
        provider.transferOwnership(BERA.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function deployConfigureBucketRateLimiter(address scriptDeployer) private returns (address) {
        address impl = CREATE3.deployCreate3(keccak256("BucketRateLimiterImpl"), type(BucketRateLimiter).creationCode);

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, 
            abi.encode(impl, BERA.L2_CONTRACT_CONTROLLER_SAFE, abi.encodeWithSelector(BucketRateLimiter.initialize.selector, scriptDeployer))
        );
        address proxy = address(CREATE3.deployCreate3(keccak256("BucketRateLimiter"), proxyCreationCode));
        console.log("Bucket Rate Limiter deployed at: ", address(proxy));
        require(address(proxy) == BERA.L2_SYNC_POOL_RATE_LIMITER, "Bucket Rate Limiter address mismatch");
        
        BucketRateLimiter limiter = BucketRateLimiter(address(proxy));
        limiter.setCapacity(BUCKET_SIZE);
        limiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        limiter.updateConsumer(BERA.L2_SYNC_POOL);
        limiter.transferOwnership(BERA.L2_CONTRACT_CONTROLLER_SAFE);

        return address(proxy);
    }

    function getEnforcedOptions(uint32 _eid) public pure returns (EnforcedOptionParam[] memory) {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: _eid,
            msgType: 0,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        });
        
        enforcedOptions[1] = EnforcedOptionParam({
            eid: _eid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        });
        enforcedOptions[2] = EnforcedOptionParam({
            eid: _eid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        });

        return enforcedOptions; 
    }

    function deployConfigureSyncPool(
        address scriptDeployer,
        address exchangeRateProvider,
        address bucketRateLimiter
    ) private returns (address) {
        address impl = CREATE3.deployCreate3(keccak256("L2SyncPoolImpl"), abi.encodePacked(type(HydraSyncPoolETHUpgradeable).creationCode, abi.encode(BERA.L2_ENDPOINT, HYDRA_WETH)));

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, 
            abi.encode(impl, BERA.L2_CONTRACT_CONTROLLER_SAFE, 
            abi.encodeWithSelector(
                HydraSyncPoolETHUpgradeable.initialize.selector, 
                exchangeRateProvider, 
                bucketRateLimiter, 
                BERA.L2_OFT, 
                L1_EID, 
                BERA.L2_MESSENGER, 
                BERA.L1_RECEIVER, 
                scriptDeployer
            )));

        address proxy = address(CREATE3.deployCreate3(keccak256("L2SyncPool"), proxyCreationCode));
        console.log("Sync Pool deployed at: ", proxy);
        require(proxy == BERA.L2_SYNC_POOL, "Sync Pool address mismatch");

        HydraSyncPoolETHUpgradeable syncPool = HydraSyncPoolETHUpgradeable(proxy);

        // set all LayerZero configurations and sync pool specific configurations
        syncPool.setPeer(L1_EID, LayerZeroHelpers._toBytes32(L1_SYNC_POOL));
        IOAppOptionsType3(proxy).setEnforcedOptions(getEnforcedOptions(L1_EID));
        ILayerZeroEndpointV2(BERA.L2_ENDPOINT).setConfig(
            address(syncPool),
            BERA.SEND_302,
            LayerZeroHelpers.getDVNConfigWithBlockConfirmations(L1_EID, BERA.LZ_DVN, 10)
        );

        // for bera wETH is the L2 input token
        syncPool.setL1TokenIn(HYDRA_WETH, Constants.ETH_ADDRESS);
        syncPool.transferOwnership(BERA.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        console.log("Deploying contracts on L2...");

        // deploy and configure the native minting related contracts
        address exchangeRateProvider = deployConfigureExchangeRateProvider(DEPLOYER_ADDRESS);
        address rateLimiter = deployConfigureBucketRateLimiter(DEPLOYER_ADDRESS);
        deployConfigureSyncPool(DEPLOYER_ADDRESS, exchangeRateProvider, rateLimiter);

        // generate the transactions required by the L2 contract controller

        // give the L2 sync pool permission to mint the dummy token
        string memory minterTransaction = _getGnosisHeader(BERA.CHAIN_ID);
        bytes memory setMinterData = abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ROLE, BERA.L2_SYNC_POOL);
        minterTransaction = string.concat(minterTransaction, _getGnosisTransaction(iToHex(abi.encodePacked(BERA.L2_OFT)), iToHex(setMinterData), true));
        vm.writeJson(minterTransaction, "./output/setBeraMinter.json");

        // transaction to set the min sync 
        string memory minSyncTransaction = _getGnosisHeader(BERA.CHAIN_ID);
        bytes memory setMinSyncData = abi.encodeWithSignature("setMinSyncAmount(address,uint256)", Constants.ETH_ADDRESS, 10 ether);
        minSyncTransaction = string.concat(minSyncTransaction, _getGnosisTransaction(iToHex(abi.encodePacked(BERA.L2_SYNC_POOL)), iToHex(setMinSyncData), true));
        vm.writeJson(minSyncTransaction, "./output/setMinSyncAmount.json");
    }
}
