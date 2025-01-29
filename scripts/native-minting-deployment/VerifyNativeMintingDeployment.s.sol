// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";
import "../../contracts/NativeMinting/ReceiverContracts/L1ScrollReceiverETHUpgradeable.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../contracts/NativeMinting/EtherfiL1SyncPoolETH.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../utils/L2Constants.sol";
import "../ContractCodeChecker.sol";

// forge script scripts/NativeMintingDeployment/VerifyNativeMintingDeployment.s.sol:verifyNativeMintingDeployment --via-ir
// verifies the bytecode and upgrade role of the native minting contracts
contract verifyNativeMintingDeployment is Script, L2Constants, ContractCodeChecker, Test {

    bytes32 _ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");

    address constant L1_DUMMY_TOKEN_IMPL = 0x96a049493ACF81f92aF84149e0CA09ae13985cD0;
    address constant L1_RECEIVER_IMPL = 0xF670aE1c81dDa2eF7Dc32007d029dF0cD10AC3fF;
    address constant L2_EXCHANGE_RATE_PROVIDER_IMPL = 0xa6be84d700A5547c9834A872ff2232aa492476EB;
    address constant L2_SYNC_POOL_RATE_LIMITER_IMPL = 0x0FECAc981af5cF94d287bff5b7A7217f5B4F7930;
    address constant L2_SYNC_POOL_IMPL = 0xD6669323D43201eAeE7183D41671a9DDA9B3d545;
    
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
            localBytecode = address(SCROLL.L1_DUMMY_TOKEN).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify L1ScrollReceiver implementation and proxy
        {
            console.log("Checking L1ScrollReceiver contracts...\n");
            bytes memory onchainBytecode = L1_RECEIVER_IMPL.code;
            bytes memory localBytecode = address(new L1ScrollReceiverETHUpgradeable()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            // Reuse previously created proxy for comparison
            onchainBytecode = address(new TransparentUpgradeableProxy(L1_DUMMY_TOKEN_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(SCROLL.L1_RECEIVER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        //------------------------------------------------------------------------------
        // L2 Chain Verification
        //------------------------------------------------------------------------------
        vm.createSelectFork(SCROLL.RPC_URL);
        console.log("\n=========== Verifying L2 Contract Bytecode ===========\n");

        // Verify ExchangeRateProvider implementation and proxy
        {
            console.log("Checking ExchangeRateProvider contracts...\n");
            bytes memory onchainBytecode = L2_EXCHANGE_RATE_PROVIDER_IMPL.code;
            bytes memory localBytecode = address(new EtherfiL2ExchangeRateProvider()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(SCROLL.L2_EXCHANGE_RATE_PROVIDER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify BucketRateLimiter implementation and proxy (uses ERC1967Proxy)
        {
            console.log("Checking BucketRateLimiter contracts...\n");
            bytes memory onchainBytecode = L2_SYNC_POOL_RATE_LIMITER_IMPL.code;
            bytes memory localBytecode = address(new BucketRateLimiter()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            // Note: This is the only cross chain contract using ERC1967Proxy instead of TransparentUpgradeableProxy
            onchainBytecode = address(new ERC1967Proxy(L2_SYNC_POOL_RATE_LIMITER_IMPL, "")).code;
            localBytecode = address(SCROLL.L2_SYNC_POOL_RATE_LIMITER).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        // Verify L2ScrollSyncPool implementation and proxy
        {
            console.log("Checking L2ScrollSyncPool contracts...\n");
            bytes memory onchainBytecode = L2_SYNC_POOL_IMPL.code;
            bytes memory localBytecode = address(new L2ScrollSyncPoolETHUpgradeable(SCROLL.L2_ENDPOINT)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
            localBytecode = address(SCROLL.L2_SYNC_POOL).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }


        console.log("\n=========== Verifying Access Control ===========\n");
            
        console.log("Checking roles on L2...\n");

        // verify the admin address stored in the storage slot
        address adminAddress = address(uint160(uint256(vm.load(SCROLL.L2_SYNC_POOL, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, SCROLL.L2_SYNC_POOL_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(SCROLL.L2_EXCHANGE_RATE_PROVIDER, bytes32(_ADMIN_SLOT))))); 
        assertEq(adminAddress, SCROLL.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN);

        // verify the L2 contract controller has all the upgrade roles
        assertEq(ProxyAdmin(SCROLL.L2_SYNC_POOL_PROXY_ADMIN).owner(), SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(ProxyAdmin(SCROLL.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN).owner(), SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(BucketRateLimiter(SCROLL.L2_SYNC_POOL_RATE_LIMITER).owner(), SCROLL.L2_CONTRACT_CONTROLLER_SAFE);
        // assertTrue(EtherfiOFTUpgradeable(SCROLL.L2_OFT).hasRole(MINTER_ROLE, SCROLL.L2_SYNC_POOL), "L2_SYNC_POOL should have MINTER_ROLE");

        console.log("ProxyAdmin Of L2_OFT: ", SCROLL.L2_OFT_PROXY_ADMIN);
        console.log("ProxyAdmin Of L2_SYNC_POOL: ", SCROLL.L2_SYNC_POOL_PROXY_ADMIN);
        console.log("ProxyAdmin Of L2_EXCHANGE_RATE_PROVIDER: ", SCROLL.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN);

        console.log("Checking roles on L1...\n");
        vm.createSelectFork(L1_RPC_URL);

        adminAddress = address(uint160(uint256(vm.load(SCROLL.L1_DUMMY_TOKEN, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, SCROLL.L1_DUMMY_TOKEN_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(SCROLL.L1_RECEIVER, bytes32(_ADMIN_SLOT)))));
        assertEq(adminAddress, SCROLL.L1_RECEIVER_PROXY_ADMIN);

        assertEq(ProxyAdmin(SCROLL.L1_DUMMY_TOKEN_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertEq(ProxyAdmin(SCROLL.L1_RECEIVER_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertTrue(DummyTokenUpgradeable(SCROLL.L1_DUMMY_TOKEN).hasRole(MINTER_ROLE, L1_SYNC_POOL), "L1_SYNC_POOL should have MINTER_ROLE");

        console.log("ProxyAdmin Of L1_DUMMY_TOKEN: ", SCROLL.L1_DUMMY_TOKEN_PROXY_ADMIN);
        console.log("ProxyAdmin Of L1_RECEIVER: ", SCROLL.L1_RECEIVER_PROXY_ADMIN);
        console.log("ProxyAdmin Of L1_SYNC_POOL: ", L1_SYNC_POOL_PROXY_ADMIN);
        
        console.log("upgrade roles verified successfully\n");
    }
}
