// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";
import "../../utils/L2Constants.sol";


contract L1NativeMintingScript is Script, L2Constants {


    /*//////////////////////////////////////////////////////////////
                    Current Deployment Parameters
    //////////////////////////////////////////////////////////////*/
    
    ConfigPerL2 public DEPLOYMENT_L2 = SCROLL;
    address constant WEETH_RATE_PROVIDER = 0x57bd9E614f542fB3d6FeF2B744f3B813f0cc1258;
    address constant L2_MESSENGER = 0x781e90f1c8Fc4611c9b7497C3B47F99Ef6969CbC;

    /*//////////////////////////////////////////////////////////////
                
    //////////////////////////////////////////////////////////////*/

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
        console.log("Sync Pool deployed at: ", syncPoolProxy);

        bucketRateLimiter.updateConsumer(syncPoolProxy);
        bucketRateLimiter.transferOwnership(DEPLOYMENT_L2.L2_CONTRACT_CONTROLLER_SAFE);
    }
}
