// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";


contract L1NativeMintingScript is Script, L2Constants, LayerZeroHelpers {

    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        console.log("Deploying contracts on L2...");

        address exchangeRateProviderImp = address(new EtherfiL2ExchangeRateProvider());
        address exchangeRateProviderProxy = address(
            new TransparentUpgradeableProxy(
                exchangeRateProviderImp, 
                DEPLOYMENT_L2.L2_CONTRACT_CONTROLLER_SAFE, 
                abi.encodeWithSelector(
                    EtherfiL2ExchangeRateProvider.initialize.selector, scriptDeployer
                )
            )
        );
        EtherfiL2ExchangeRateProvider exchangeRateProvider = EtherfiL2ExchangeRateProvider(exchangeRateProviderProxy);
        exchangeRateProvider.setRateParameters(ETH_ADDRESS, WEETH_RATE_PROVIDER, 0, L2_PRICE_ORACLE_HEART_BEAT);
        exchangeRateProvider.transferOwnership(DEPLOYMENT_L2.L2_CONTRACT_CONTROLLER_SAFE);
        console.log("Exchange Rate Provider deployed at: ", address(exchangeRateProviderProxy));

        // BucketRateLimiter is our only native minting contract that uses UUPS
        address bucketRateLimiterImp = address(new BucketRateLimiter());
        ERC1967Proxy bucketRateLimitierProxy = new ERC1967Proxy(bucketRateLimiterImp, abi.encodeWithSelector(BucketRateLimiter.initialize.selector));
        BucketRateLimiter bucketRateLimiter = BucketRateLimiter(address(bucketRateLimitierProxy));
        bucketRateLimiter.initialize(scriptDeployer);
        bucketRateLimiter.setCapacity(BUCKET_SIZE);
        bucketRateLimiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        console.log("Bucket Rate Limiter deployed at: ", address(bucketRateLimitierProxy));

        address syncPoolImp = address(new L2ScrollSyncPoolETHUpgradeable(DEPLOYMENT_L2.L2_ENDPOINT));
        address syncPoolProxy = address(
            new TransparentUpgradeableProxy(
                syncPoolImp, 
                DEPLOYMENT_L2.L2_CONTRACT_CONTROLLER_SAFE, 
                abi.encodeWithSelector(
                    L2ScrollSyncPoolETHUpgradeable.initialize.selector, 
                    exchangeRateProviderProxy,
                    bucketRateLimitierProxy,
                    L1_EID,
                    DEPLOYMENT_L2.L2_OFT,
                    L2_MESSENGER,
                    address(0), // Receiver contract hasn't been deployed on mainnet yet
                    scriptDeployer
                )
            )
        );
        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(syncPoolProxy);
        console.log("Sync Pool deployed at: ", syncPoolProxy);

        bucketRateLimiter.updateConsumer(syncPoolProxy);
        bucketRateLimiter.transferOwnership(DEPLOYMENT_L2.L2_CONTRACT_CONTROLLER_SAFE);

        // setting OFT config for the L2 sync pool
        syncPool.setPeer(L1_EID, _toBytes32(L1_SYNC_POOL));

        ILayerZeroEndpointV2(DEPLOYMENT_L2.L2_ENDPOINT).setConfig(syncPoolProxy, DEPLOYMENT_SEND_LID_302, params);

        SetConfigParam[] memory params = new SetConfigParam[](1);
    
        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: DEPLOYMENT_L2.L2_DVNS,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(DEPLOYMENT_L2.L2_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_L2.SEND_302, params);

    }
}
