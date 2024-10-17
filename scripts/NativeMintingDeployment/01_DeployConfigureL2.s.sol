// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract L2NativeMintingScript is Script, L2Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;


    EnforcedOptionParam[] public enforcedOptions;
    
    address constant WEETH_RATE_PROVIDER = 0x57bd9E614f542fB3d6FeF2B744f3B813f0cc1258;
    address constant L2_MESSENGER = 0x781e90f1c8Fc4611c9b7497C3B47F99Ef6969CbC;

    function deployExchangeRateProvider(address scriptDeployer) private returns (address) {
        address impl = address(new EtherfiL2ExchangeRateProvider());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(
                    EtherfiL2ExchangeRateProvider.initialize.selector,
                    scriptDeployer
                )
            )
        );
        
        EtherfiL2ExchangeRateProvider provider = EtherfiL2ExchangeRateProvider(proxy);
        provider.setRateParameters(ETH_ADDRESS, WEETH_RATE_PROVIDER, 0, L2_PRICE_ORACLE_HEART_BEAT);
        provider.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        
        console.log("Exchange Rate Provider deployed at: ", proxy);
        return proxy;
    }

    function deployBucketRateLimiter(address scriptDeployer) private returns (address) {
        address impl = address(new BucketRateLimiter());
        ERC1967Proxy proxy = new ERC1967Proxy(
            impl,
            abi.encodeWithSelector(BucketRateLimiter.initialize.selector, scriptDeployer)
        );
        
        BucketRateLimiter limiter = BucketRateLimiter(address(proxy));
        limiter.setCapacity(BUCKET_SIZE);
        limiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        
        console.log("Bucket Rate Limiter deployed at: ", address(proxy));
        return address(proxy);
    }

    function deploySyncPool(
        address scriptDeployer,
        address exchangeRateProvider,
        address bucketRateLimiter
    ) private returns (address) {
        address impl = address(new L2ScrollSyncPoolETHUpgradeable(SCROLL.L2_ENDPOINT));
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(
                    L2ScrollSyncPoolETHUpgradeable.initialize.selector,
                    exchangeRateProvider,
                    bucketRateLimiter,
                    SCROLL.L2_OFT,
                    L1_EID,
                    L2_MESSENGER,
                    address(0),
                    scriptDeployer
                )
            )
        );
        
        console.log("Sync Pool deployed at: ", proxy);
        return proxy;
    }

    function run() public returns (address) {
        address scriptDeployer = vm.addr(1);
        vm.startPrank(scriptDeployer);

        console.log("Deploying contracts on L2...");

        address exchangeRateProvider = deployExchangeRateProvider(scriptDeployer);
        address rateLimiter = deployBucketRateLimiter(scriptDeployer);
        address syncPool = deploySyncPool(scriptDeployer, exchangeRateProvider, rateLimiter);

        // Configure the deployed contracts
        BucketRateLimiter(rateLimiter).updateConsumer(syncPool);
        BucketRateLimiter(rateLimiter).transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        L2ScrollSyncPoolETHUpgradeable(syncPool).setPeer(L1_EID, _toBytes32(L1_SYNC_POOL));
        ILayerZeroEndpointV2(SCROLL.L2_ENDPOINT).setConfig(
            syncPool,
            SCROLL.SEND_302,
            getDVNConfig(L1_EID, SCROLL.LZ_DVN)
        );
        IOAppOptionsType3(syncPool).setEnforcedOptions(getEnforcedOptions(L1_EID));

        L2ScrollSyncPoolETHUpgradeable(syncPool).setL1TokenIn(Constants.ETH_ADDRESS, Constants.ETH_ADDRESS);
        
        vm.stopPrank();

        return syncPool;
    }
}
