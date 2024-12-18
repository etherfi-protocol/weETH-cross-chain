// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../contracts/NativeMinting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/NativeMinting/BucketRateLimiter.sol";
import "../../contracts/NativeMinting/ReceiverContracts/L1ScrollReceiverETHUpgradeable.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../utils/L2Constants.sol";
import "../ContractCodeChecker.sol";

// forge script scripts/NativeMintingDeployment/VerifyNativeMintingBytecode.s.sol:verifyNativeMintingBytecode --via-ir
contract verifyNativeMintingBytecode is Script, L2Constants, ContractCodeChecker {

    address constant L1_DUMMY_TOKEN_IMPL = 0x96a049493ACF81f92aF84149e0CA09ae13985cD0;
    address constant L1_RECEIVER_IMPL = 0xF670aE1c81dDa2eF7Dc32007d029dF0cD10AC3fF;

    address constant L2_EXCHANGE_RATE_PROVIDER_IMPL = 0xa6be84d700A5547c9834A872ff2232aa492476EB;
    address constant L2_SYNC_POOL_RATE_LIMITER = 0x0FECAc981af5cF94d287bff5b7A7217f5B4F7930;
    address constant L2_SYNC_POOL_IMPL = 0xD6669323D43201eAeE7183D41671a9DDA9B3d545;
    
    function run() public {

    //------------------------------------------------------------------------------
    // L1 Chain Verification
    //------------------------------------------------------------------------------
    vm.createSelectFork(L1_RPC_URL);
    console.log("\n=== Verifying L1 Chain Contracts ===\n");

    // Verify DummyToken implementation and proxy
    {
        console.log("Checking DummyToken contracts...");
        bytes memory onchainBytecode = L1_DUMMY_TOKEN_IMPL.code;
        bytes memory localBytecode = address(new DummyTokenUpgradeable(18)).code;
        bool lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Implementation bytecode lengths match:", lengthsMatch);
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

        // Create proxy instance for comparison (constructor args don't affect bytecode)
        onchainBytecode = address(new TransparentUpgradeableProxy(L1_DUMMY_TOKEN_IMPL, DEPLOYER_ADDRESS, "")).code;
        localBytecode = address(SCROLL.L1_DUMMY_TOKEN).code;
        lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Proxy bytecode lengths match:", lengthsMatch);
        console.log("");
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
    }

    // Verify L1ScrollReceiver implementation and proxy
    {
        console.log("Checking L1ScrollReceiver contracts...");
        bytes memory onchainBytecode = L1_RECEIVER_IMPL.code;
        bytes memory localBytecode = address(new L1ScrollReceiverETHUpgradeable()).code;
        bool lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Implementation bytecode lengths match:", lengthsMatch);
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

        // Reuse previously created proxy for comparison
        onchainBytecode = address(new TransparentUpgradeableProxy(L1_DUMMY_TOKEN_IMPL, DEPLOYER_ADDRESS, "")).code;
        localBytecode = address(SCROLL.L1_RECEIVER).code;
        lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Proxy bytecode lengths match:", lengthsMatch);
        console.log("");
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
    }

    //------------------------------------------------------------------------------
    // L2 Chain Verification
    //------------------------------------------------------------------------------
    vm.createSelectFork(SCROLL.RPC_URL);
    console.log("\n=== Verifying L2 Chain Contracts ===\n");

    // Verify ExchangeRateProvider implementation and proxy
    {
        console.log("Checking ExchangeRateProvider contracts...");
        bytes memory onchainBytecode = L2_EXCHANGE_RATE_PROVIDER_IMPL.code;
        bytes memory localBytecode = address(new EtherfiL2ExchangeRateProvider()).code;
        bool lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Implementation bytecode lengths match:", lengthsMatch);
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

        onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
        localBytecode = address(SCROLL.L2_EXCHANGE_RATE_PROVIDER).code;
        lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Proxy bytecode lengths match:", lengthsMatch);
        console.log("");
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
    }

    // Verify BucketRateLimiter implementation and proxy (uses ERC1967Proxy)
    {
        console.log("Checking BucketRateLimiter contracts...");
        bytes memory onchainBytecode = L2_SYNC_POOL_RATE_LIMITER.code;
        bytes memory localBytecode = address(new BucketRateLimiter()).code;
        bool lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Implementation bytecode lengths match:", lengthsMatch);
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

        // Note: This is the only cross chain contract using ERC1967Proxy instead of TransparentUpgradeableProxy
        onchainBytecode = address(new ERC1967Proxy(L2_SYNC_POOL_RATE_LIMITER, "")).code;
        localBytecode = address(SCROLL.L2_SYNC_POOL_RATE_LIMITER).code;
        lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Proxy bytecode lengths match:", lengthsMatch);
        console.log("");
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
    }

    // Verify L2ScrollSyncPool implementation and proxy
    {
        console.log("Checking L2ScrollSyncPool contracts...");
        bytes memory onchainBytecode = L2_SYNC_POOL_IMPL.code;
        bytes memory localBytecode = address(new L2ScrollSyncPoolETHUpgradeable(SCROLL.L2_ENDPOINT)).code;
        bool lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Implementation bytecode lengths match:", lengthsMatch);
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

        onchainBytecode = address(new TransparentUpgradeableProxy(L2_EXCHANGE_RATE_PROVIDER_IMPL, DEPLOYER_ADDRESS, "")).code;
        localBytecode = address(SCROLL.L2_SYNC_POOL).code;
        lengthsMatch = onchainBytecode.length == localBytecode.length;
        console.log("- Proxy bytecode lengths match:", lengthsMatch);
        console.log("");
        verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
    }
}
}
