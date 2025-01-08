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
import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";

import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../../utils/GnosisHelpers.sol";

contract L2NativeMintingScript is Script, L2Constants, LayerZeroHelpers, GnosisHelpers {
    using OptionsBuilder for bytes;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    EnforcedOptionParam[] public enforcedOptions;

    function deployConfigureExchangeRateProvider(address scriptDeployer) private returns (address) {
        address impl = address(new EtherfiL2ExchangeRateProvider{salt: keccak256("ExchangeRateProviderImpl")}());
        address proxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("ExchangeRateProvider")}(
                impl,
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(
                    EtherfiL2ExchangeRateProvider.initialize.selector,
                    scriptDeployer
                )
            )
        );
        console.log("Exchange Rate Provider deployed at: ", proxy);
        require(proxy == SCROLL.L2_EXCHANGE_RATE_PROVIDER, "Exchange Rate Provider address mismatch");
        
        EtherfiL2ExchangeRateProvider provider = EtherfiL2ExchangeRateProvider(proxy);
        provider.setRateParameters(ETH_ADDRESS, SCROLL.L2_PRICE_ORACLE, 0, L2_PRICE_ORACLE_HEART_BEAT);
        provider.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function deployConfigureBucketRateLimiter(address scriptDeployer) private returns (address) {
        address impl = address(new BucketRateLimiter{salt: keccak256("BucketRateLimiterImpl")}());
        ERC1967Proxy proxy = new ERC1967Proxy{salt: keccak256("BucketRateLimiter")}(
            impl,
            abi.encodeWithSelector(BucketRateLimiter.initialize.selector, scriptDeployer)
        );
        console.log("Bucket Rate Limiter deployed at: ", address(proxy));
        require(address(proxy) == SCROLL.L2_SYNC_POOL_RATE_LIMITER, "Bucket Rate Limiter address mismatch");
        
        BucketRateLimiter limiter = BucketRateLimiter(address(proxy));
        limiter.setCapacity(BUCKET_SIZE);
        limiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        limiter.updateConsumer(SCROLL.L2_SYNC_POOL);
        limiter.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        return address(proxy);
    }

    function deployConfigureSyncPool(
        address scriptDeployer,
        address exchangeRateProvider,
        address bucketRateLimiter
    ) private returns (address) {
        address impl = address(new L2ScrollSyncPoolETHUpgradeable{salt: keccak256("L2SyncPoolImpl")}(SCROLL.L2_ENDPOINT));
        address proxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("L2SyncPool")}(
                impl,
                SCROLL.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(
                    L2ScrollSyncPoolETHUpgradeable.initialize.selector,
                    exchangeRateProvider,
                    bucketRateLimiter,
                    SCROLL.L2_OFT,
                    L1_EID,
                    SCROLL.L2_MESSENGER,
                    SCROLL.L1_RECEIVER,
                    scriptDeployer
                )
            )
        );

        console.log("Sync Pool deployed at: ", proxy);
        require(proxy == SCROLL.L2_SYNC_POOL, "Sync Pool address mismatch");

        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(proxy);

        // set all LayerZero configurations and sync pool specific configurations
        syncPool.setPeer(L1_EID, _toBytes32(L1_SYNC_POOL));
        IOAppOptionsType3(proxy).setEnforcedOptions(getEnforcedOptions(L1_EID));
        ILayerZeroEndpointV2(SCROLL.L2_ENDPOINT).setConfig(
            address(syncPool),
            SCROLL.SEND_302,
            getDVNConfig(L1_EID, SCROLL.LZ_DVN)
        );

        syncPool.setL1TokenIn(Constants.ETH_ADDRESS, Constants.ETH_ADDRESS);
        syncPool.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        console.log("Deploying contracts on L2...");
        
        // Contracts are already deployed
        // deploy and configure the native minting related contracts
        // address exchangeRateProvider = deployConfigureExchangeRateProvider(DEPLOYER_ADDRESS);
        // address rateLimiter = deployConfigureBucketRateLimiter(DEPLOYER_ADDRESS);
        // deployConfigureSyncPool(DEPLOYER_ADDRESS, exchangeRateProvider, rateLimiter);

        // generate the transactions required by the L2 contract controller

        // give the L2 sync pool permission to mint the dummy token
        string memory minterTransaction = _getGnosisHeader(SCROLL.CHAIN_ID);
        bytes memory setMinterData = abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ROLE, SCROLL.L2_SYNC_POOL);
        minterTransaction = string.concat(minterTransaction, _getGnosisTransaction(iToHex(abi.encodePacked(SCROLL.L2_OFT)), iToHex(setMinterData), true));
        vm.writeJson(minterTransaction, "./output/setScrollMinter.json");

        // transaction to set the min sync 
        string memory minSyncTransaction = _getGnosisHeader(SCROLL.CHAIN_ID);
        bytes memory setMinSyncData = abi.encodeWithSignature("setMinSyncAmount(address,uint256)", Constants.ETH_ADDRESS, 10 ether);
        minSyncTransaction = string.concat(minSyncTransaction, _getGnosisTransaction(iToHex(abi.encodePacked(SCROLL.L2_SYNC_POOL)), iToHex(setMinSyncData), true));
        vm.writeJson(minSyncTransaction, "./output/setMinSyncAmount.json");
    }
}
