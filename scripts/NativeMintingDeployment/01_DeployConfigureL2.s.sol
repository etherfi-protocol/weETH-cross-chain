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
    address public syncPoolProxy;

    /*//////////////////////////////////////////////////////////////
                            Deployment Config
    //////////////////////////////////////////////////////////////*/

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
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE, 
                abi.encodeWithSelector(
                    EtherfiL2ExchangeRateProvider.initialize.selector, scriptDeployer
                )
            )
        );
        EtherfiL2ExchangeRateProvider exchangeRateProvider = EtherfiL2ExchangeRateProvider(exchangeRateProviderProxy);
        exchangeRateProvider.setRateParameters(ETH_ADDRESS, WEETH_RATE_PROVIDER, 0, L2_PRICE_ORACLE_HEART_BEAT);
        exchangeRateProvider.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        console.log("Exchange Rate Provider deployed at: ", address(exchangeRateProviderProxy));

        // BucketRateLimiter is our only native minting contract that uses UUPS
        address bucketRateLimiterImp = address(new BucketRateLimiter());
        ERC1967Proxy bucketRateLimitierProxy = new ERC1967Proxy(bucketRateLimiterImp, abi.encodeWithSelector(BucketRateLimiter.initialize.selector));
        BucketRateLimiter bucketRateLimiter = BucketRateLimiter(address(bucketRateLimitierProxy));
        bucketRateLimiter.initialize(scriptDeployer);
        bucketRateLimiter.setCapacity(BUCKET_SIZE);
        bucketRateLimiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        console.log("Bucket Rate Limiter deployed at: ", address(bucketRateLimitierProxy));

        address syncPoolImp = address(new L2ScrollSyncPoolETHUpgradeable(SCROLL.L2_ENDPOINT));
        syncPoolProxy = address(
            new TransparentUpgradeableProxy(
                syncPoolImp, 
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE, 
                abi.encodeWithSelector(
                    L2ScrollSyncPoolETHUpgradeable.initialize.selector, 
                    exchangeRateProviderProxy,
                    bucketRateLimitierProxy,
                    L1_EID,
                    SCROLL.L2_OFT,
                    L2_MESSENGER,
                    address(0), // Receiver contract hasn't been deployed on mainnet yet
                    scriptDeployer
                )
            )
        );

        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(syncPoolProxy);
        console.log("Sync Pool deployed at: ", syncPoolProxy);

        bucketRateLimiter.updateConsumer(syncPoolProxy);
        bucketRateLimiter.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        // set OFT configurations for the L2 sync pool
        syncPool.setPeer(L1_EID, _toBytes32(L1_SYNC_POOL));
        _setDVN();

        IOAppOptionsType3(syncPoolProxy).setEnforcedOptions(getEnforcedOptions(L1_EID));
    }

    function _setDVN() internal {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = SCROLL.LZ_DVN[0];
        requiredDVNs[1] = SCROLL.LZ_DVN[1];
        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(L1_EID, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(SCROLL.L2_ENDPOINT).setConfig(syncPoolProxy, SCROLL.SEND_302, params);
    }
}
