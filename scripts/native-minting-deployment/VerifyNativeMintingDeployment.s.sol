// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "../../contracts/native-minting/DummyTokenUpgradeable.sol";
import "../../contracts/native-minting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/native-minting/BucketRateLimiter.sol";
import "../../contracts/native-minting/receivers/L1HydraReceiverETHUpgradeable.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../../contracts/native-minting/l2-syncpools/HydraSyncPoolETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../utils/L2Constants.sol";
import "../ContractCodeChecker.sol";

// forge script scripts/native-minting-deployment/VerifyNativeMintingDeployment.s.sol:VerifyNativeMintingDeployment --via-ir
// verifies the bytecode and upgrade role of the native minting contracts
contract VerifyNativeMintingDeployment is Script, L2Constants, ContractCodeChecker, Test {

    bytes32 _ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");

    address constant L1_DUMMY_TOKEN_IMPL = 0x3B113Cd6251003E251a695A3770D3A2446075D45;
    address constant L1_RECEIVER_IMPL = 0x4422499CF72ed1b0700a62Dde17C9e76aB808B07;
    address constant L2_EXCHANGE_RATE_PROVIDER_IMPL = 0x2727b811478DdB339033057B8471ab3Eb8331594;
    address constant L2_SYNC_POOL_RATE_LIMITER_IMPL = 0xac0f8745c9FC96986B63749697ae693f312f5B29;
    address constant L2_SYNC_POOL_IMPL = 0xAEAe84d0858BC009Ff460c50EaA75f15b02671dC;

    // addition constants for hydra deployment
    // hydra deployed wETH on bera
    address constant HYDRA_WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // StargateOFTETH deployed on bera
    address constant STARGATE_OFT_ETH = 0x45f1A95A4D3f3836523F5c83673c797f4d4d263B;

    address constant STARGATE_POOL_NATIVE = 0x77b2043768d28E9C9aB44E1aBfC95944bcE57931;
    
    function run() public {

        //------------------------------------------------------------------------------
        // L1 Chain Verification
        //------------------------------------------------------------------------------
        vm.createSelectFork(L1_RPC_URL);
        console.log("\n=========== Verifying L1 Contract Bytecode ===========\n");

        // Verify DummyToken implementation and proxy
        {
            console.log("Checking DummyToken contracts...\n");
            bytes memory onchainBytecode = L1_DUMMY_TOKEN_IMPL.code;
            bytes memory localBytecode = address(new DummyTokenUpgradeable(18)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            // Create proxy instance for comparison (constructor args don't affect bytecode)
            onchainBytecode = address(new TransparentUpgradeableProxy(L1_DUMMY_TOKEN_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(BERA.L1_DUMMY_TOKEN).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify receiver implementation and proxy
        {
            console.log("Checking receiver contracts...\n");
            bytes memory onchainBytecode = L1_RECEIVER_IMPL.code;
            bytes memory localBytecode = address(new L1HydraReceiverETHUpgradeable(STARGATE_POOL_NATIVE)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            // Reuse previously created proxy for comparison
            onchainBytecode = address(new TransparentUpgradeableProxy(L1_DUMMY_TOKEN_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(BERA.L1_RECEIVER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        //------------------------------------------------------------------------------
        // L2 Chain Verification
        //------------------------------------------------------------------------------
        vm.createSelectFork(BERA.RPC_URL);
        console.log("\n=========== Verifying L2 Contract Bytecode ===========\n");

        // Verify ExchangeRateProvider implementation and proxy
        {
            console.log("Checking ExchangeRateProvider contracts...\n");
            bytes memory onchainBytecode = L2_EXCHANGE_RATE_PROVIDER_IMPL.code;
            bytes memory localBytecode = address(new EtherfiL2ExchangeRateProvider()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(BERA.L2_EXCHANGE_RATE_PROVIDER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify BucketRateLimiter implementation and proxy (uses ERC1967Proxy)
        {
            console.log("Checking BucketRateLimiter contracts...\n");
            bytes memory onchainBytecode = L2_SYNC_POOL_RATE_LIMITER_IMPL.code;
            bytes memory localBytecode = address(new BucketRateLimiter()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(L2_SYNC_POOL_RATE_LIMITER_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(BERA.L2_SYNC_POOL_RATE_LIMITER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify sync pool implementation and proxy
        {
            console.log("Checking sync pool contracts...\n");
            bytes memory onchainBytecode = L2_SYNC_POOL_IMPL.code;
            bytes memory localBytecode = address(new HydraSyncPoolETHUpgradeable(BERA.L2_ENDPOINT, HYDRA_WETH)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(BERA.L2_SYNC_POOL).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }


        console.log("\n=========== Verifying Access Control ===========\n");
            
        console.log("Checking roles on L2...\n");

        // verify the admin address stored in the storage slot
        address adminAddress = address(uint160(uint256(vm.load(BERA.L2_SYNC_POOL, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, BERA.L2_SYNC_POOL_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(BERA.L2_EXCHANGE_RATE_PROVIDER, bytes32(_ADMIN_SLOT))))); 
        assertEq(adminAddress, BERA.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(BERA.L2_SYNC_POOL_RATE_LIMITER, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, BERA.L2_SYNC_POOL_RATE_LIMITER_PROXY_ADMIN);

        // verify the L2 contract controller has all the upgrade roles
        assertEq(ProxyAdmin(BERA.L2_SYNC_POOL_PROXY_ADMIN).owner(), BERA.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(ProxyAdmin(BERA.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN).owner(), BERA.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(ProxyAdmin(BERA.L2_SYNC_POOL_RATE_LIMITER_PROXY_ADMIN).owner(), BERA.L2_CONTRACT_CONTROLLER_SAFE);

        console.log("Checking roles on L1...\n");
        vm.createSelectFork(L1_RPC_URL);

        adminAddress = address(uint160(uint256(vm.load(BERA.L1_DUMMY_TOKEN, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, BERA.L1_DUMMY_TOKEN_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(BERA.L1_RECEIVER, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, BERA.L1_RECEIVER_PROXY_ADMIN);

        assertEq(ProxyAdmin(BERA.L1_DUMMY_TOKEN_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertEq(ProxyAdmin(BERA.L1_RECEIVER_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertTrue(DummyTokenUpgradeable(BERA.L1_DUMMY_TOKEN).hasRole(MINTER_ROLE, L1_SYNC_POOL), "L1_SYNC_POOL should have MINTER_ROLE");
        
        console.log("upgrade roles verified successfully\n");
    }
}
