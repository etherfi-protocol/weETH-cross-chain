// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "../../contracts/native-minting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/native-minting/l2-syncpools/L2OPStackSyncPoolETHUpgradeable.sol";
import "../../contracts/native-minting/BucketRateLimiter.sol";
import "../../contracts/libraries/Constants.sol";

import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../../utils/GnosisHelpers.sol";
import "../../interfaces/ICreate3Deployer.sol";

// forge script scripts/native-minting-deployment/DeployConfigureL2OPStack.s.sol:DeployConfigureL2OPStack --evm-version "shanghai" --via-ir
contract DeployConfigureL2OPStack is Script, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    bool public skipDeployment;

    // function setUp() public {
    //     skipDeployment = vm.envBool("SKIP_DEPLOYMENT");
    // }

    function getTargetChain() internal view returns (ConfigPerL2 storage) {
        string memory chain = vm.envString("TARGET_CHAIN");
        bytes32 chainHash = keccak256(bytes(chain));


        if (chainHash == keccak256("op")) return OP;
        if (chainHash == keccak256("scroll")) return SCROLL;
        if (chainHash == keccak256("ink")) return INK;

        revert("DeployConfigureL2OPStack: unknown TARGET_CHAIN");
    }

    function getSalt(string memory label) internal pure returns (bytes32) {
        return keccak256(bytes(label));
    }

    function deployExchangeRateProvider(ConfigPerL2 storage config) internal returns (address) {
        address impl = CREATE3.deployCreate3(
            getSalt("ExchangeRateProviderImpl"),
            type(EtherfiL2ExchangeRateProvider).creationCode
        );

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                config.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(EtherfiL2ExchangeRateProvider.initialize.selector, DEPLOYER_ADDRESS)
            )
        );
        address proxy = CREATE3.deployCreate3(getSalt("ExchangeRateProvider"), proxyCreationCode);
        console.log("ExchangeRateProvider deployed at:", proxy);
        require(proxy == config.L2_EXCHANGE_RATE_PROVIDER, "ExchangeRateProvider address mismatch");

        EtherfiL2ExchangeRateProvider provider = EtherfiL2ExchangeRateProvider(proxy);
        provider.setRateParameters(Constants.ETH_ADDRESS, config.L2_PRICE_ORACLE, 0, L2_PRICE_ORACLE_HEART_BEAT);
        provider.transferOwnership(config.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function deployBucketRateLimiter(ConfigPerL2 storage config) internal returns (address) {
        address impl = CREATE3.deployCreate3(
            getSalt("BucketRateLimiterImpl"),
            type(BucketRateLimiter).creationCode
        );

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                config.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(BucketRateLimiter.initialize.selector, DEPLOYER_ADDRESS)
            )
        );
        address proxy = CREATE3.deployCreate3(getSalt("BucketRateLimiter"), proxyCreationCode);
        console.log("BucketRateLimiter deployed at:", proxy);
        require(proxy == config.L2_SYNC_POOL_RATE_LIMITER, "BucketRateLimiter address mismatch");

        BucketRateLimiter limiter = BucketRateLimiter(proxy);
        limiter.setCapacity(BUCKET_SIZE);
        limiter.setRefillRatePerSecond(BUCKET_REFILL_PER_SECOND);
        limiter.updateConsumer(config.L2_SYNC_POOL);
        limiter.transferOwnership(config.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function deploySyncPool(
        ConfigPerL2 storage config,
        address exchangeRateProvider,
        address bucketRateLimiter
    ) internal returns (address) {
        address impl = CREATE3.deployCreate3(
            getSalt("L2SyncPoolImpl"),
            abi.encodePacked(type(L2OPStackSyncPoolETHUpgradeable).creationCode, abi.encode(config.L2_ENDPOINT))
        );

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                config.L2_CONTRACT_CONTROLLER_SAFE,
                abi.encodeWithSelector(
                    L2OPStackSyncPoolETHUpgradeable.initialize.selector,
                    exchangeRateProvider,
                    bucketRateLimiter,
                    config.L2_OFT,
                    L1_EID,
                    config.L2_MESSENGER,
                    config.L1_RECEIVER,
                    DEPLOYER_ADDRESS
                )
            )
        );
        address proxy = CREATE3.deployCreate3(getSalt("L2SyncPool"), proxyCreationCode);
        console.log("L2SyncPool deployed at:", proxy);
        require(proxy == config.L2_SYNC_POOL, "L2SyncPool address mismatch");

        L2OPStackSyncPoolETHUpgradeable syncPool = L2OPStackSyncPoolETHUpgradeable(proxy);

        syncPool.setPeer(L1_EID, LayerZeroHelpers._toBytes32(L1_SYNC_POOL));
        IOAppOptionsType3(proxy).setEnforcedOptions(getEnforcedOptions(L1_EID));
        ILayerZeroEndpointV2(config.L2_ENDPOINT).setConfig(
            address(syncPool),
            config.SEND_302,
            LayerZeroHelpers.getDVNConfigWithBlockConfirmations(L1_EID, config.LZ_DVN, 64)
        );

        syncPool.setL1TokenIn(Constants.ETH_ADDRESS, Constants.ETH_ADDRESS);
        syncPool.transferOwnership(config.L2_CONTRACT_CONTROLLER_SAFE);

        return proxy;
    }

    function getEnforcedOptions(uint32 _eid) internal pure returns (EnforcedOptionParam[] memory) {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: _eid,
            msgType: 0,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: _eid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });
        enforcedOptions[2] = EnforcedOptionParam({
            eid: _eid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });
        return enforcedOptions;
    }

    function getGrantMinterTransactions(ConfigPerL2 storage config) internal view returns (string memory) {
        string memory txs = _getGnosisHeader(config.CHAIN_ID, config.L2_CONTRACT_CONTROLLER_SAFE);

        bytes memory grantMinterData = abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ROLE, config.L2_SYNC_POOL);
        txs = string.concat(
            txs,
            _getGnosisTransaction(iToHex(abi.encodePacked(config.L2_OFT)), iToHex(grantMinterData), true)
        );

        return txs;
    }

    function getSetMinSyncTransactions(ConfigPerL2 storage config) internal view returns (string memory) {
        string memory txs = _getGnosisHeader(config.CHAIN_ID, config.L2_CONTRACT_CONTROLLER_SAFE);

        bytes memory setMinSyncData = abi.encodeWithSignature("setMinSyncAmount(address,uint256)", Constants.ETH_ADDRESS, 0.01 ether);
        txs = string.concat(
            txs,
            _getGnosisTransaction(iToHex(abi.encodePacked(config.L2_SYNC_POOL)), iToHex(setMinSyncData), true)
        );

        return txs;
    }

    function testDepositAndSync(ConfigPerL2 storage config) internal {
        console.log("--- Testing deposit and sync flow ---");

        L2OPStackSyncPoolETHUpgradeable syncPool = L2OPStackSyncPoolETHUpgradeable(payable(config.L2_SYNC_POOL));

        // Warp forward so the bucket rate limiter refills after fresh deployment
        vm.warp(block.timestamp + 1 hours);

        address testUser = address(0xBEEF);
        uint256 depositAmount = 0.1 ether;
        vm.deal(testUser, 10 ether);
        vm.startPrank(testUser);

        uint256 amountOut = syncPool.deposit{value: depositAmount}(Constants.ETH_ADDRESS, depositAmount, 0);
        console.log("Deposited ETH:", depositAmount);
        console.log("Received weETH:", amountOut);
        require(amountOut > 0, "No weETH minted");

        MessagingFee memory fee = syncPool.quoteSync(Constants.ETH_ADDRESS, "", false);
        console.log("Sync LZ fee:", fee.nativeFee);

        (uint256 unsyncedIn, uint256 unsyncedOut) = syncPool.sync{value: fee.nativeFee}(
            Constants.ETH_ADDRESS, "", fee
        );
        console.log("Synced amountIn:", unsyncedIn);
        console.log("Synced amountOut:", unsyncedOut);

        vm.stopPrank();
        console.log("--- Deposit and sync test passed ---");
    }

    function run() public {
        ConfigPerL2 storage config = getTargetChain();
        console.log("Target chain:", config.NAME);

        vm.createDir("./output", true);

        string memory minterPath = string.concat("./output/", config.NAME, "_L2_GrantMinter.json");
        string memory minSyncPath = string.concat("./output/", config.NAME, "_L2_SetMinSync.json");

        vm.writeJson(getGrantMinterTransactions(config), minterPath);
        vm.writeJson(getSetMinSyncTransactions(config), minSyncPath);

        console.log("Simulating gnosis transaction bundles...");
        executeGnosisTransactionBundle(minterPath, config.L2_CONTRACT_CONTROLLER_SAFE);
        executeGnosisTransactionBundle(minSyncPath, config.L2_CONTRACT_CONTROLLER_SAFE);
        console.log("All transaction bundles simulated successfully");

        testDepositAndSync(config);
    }
}
