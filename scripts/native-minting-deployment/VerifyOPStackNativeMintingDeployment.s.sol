// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "../../contracts/native-minting/DummyTokenUpgradeable.sol";
import "../../contracts/native-minting/EtherfiL2ExchangeRateProvider.sol";
import "../../contracts/native-minting/BucketRateLimiter.sol";
import "../../contracts/native-minting/receivers/L1ScrollReceiverETHUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../../contracts/native-minting/l2-syncpools/L2OPStackSyncPoolETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../utils/L2Constants.sol";
import "../ContractCodeChecker.sol";

// forge script scripts/native-minting-deployment/VerifyOPStackNativeMintingDeployment.s.sol:VerifyOPStackNativeMintingDeployment --via-ir
contract VerifyOPStackNativeMintingDeployment is Script, L2Constants, ContractCodeChecker, Test {

    bytes32 _ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 _IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");

    function readImplAddress(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPL_SLOT))));
    }

    function run() public {

        //----------------------------------------------------------------------
        // L1 Chain Verification
        //----------------------------------------------------------------------
        vm.createSelectFork(L1_RPC_URL);
        console.log("\n=========== Verifying L1 Contract Bytecode ===========\n");

        {
            console.log("Checking DummyToken contracts...\n");
            address dummyTokenImpl = readImplAddress(OP.L1_DUMMY_TOKEN);
            console.log("DummyToken impl:", dummyTokenImpl);

            bytes memory onchainBytecode = dummyTokenImpl.code;
            bytes memory localBytecode = address(new DummyTokenUpgradeable(18)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(dummyTokenImpl, DEPLOYER_ADDRESS, "")).code;
            localBytecode = OP.L1_DUMMY_TOKEN.code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        {
            console.log("Checking L1 Receiver contracts...\n");
            address receiverImpl = readImplAddress(OP.L1_RECEIVER);
            console.log("Receiver impl:", receiverImpl);

            bytes memory onchainBytecode = receiverImpl.code;
            bytes memory localBytecode = address(new L1ScrollReceiverETHUpgradeable()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(receiverImpl, DEPLOYER_ADDRESS, "")).code;
            localBytecode = OP.L1_RECEIVER.code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        console.log("\n=========== Verifying L1 Access Control ===========\n");

        address adminAddress = address(uint160(uint256(vm.load(OP.L1_DUMMY_TOKEN, _ADMIN_SLOT))));
        assertEq(adminAddress, OP.L1_DUMMY_TOKEN_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(OP.L1_RECEIVER, _ADMIN_SLOT))));
        assertEq(adminAddress, OP.L1_RECEIVER_PROXY_ADMIN);

        assertEq(ProxyAdmin(OP.L1_DUMMY_TOKEN_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertEq(ProxyAdmin(OP.L1_RECEIVER_PROXY_ADMIN).owner(), L1_TIMELOCK);
        assertTrue(DummyTokenUpgradeable(OP.L1_DUMMY_TOKEN).hasRole(MINTER_ROLE, L1_SYNC_POOL), "L1_SYNC_POOL should have MINTER_ROLE");

        console.log("L1 access control verified successfully\n");

        //----------------------------------------------------------------------
        // L2 Chain Verification
        //----------------------------------------------------------------------
        vm.createSelectFork(OP.RPC_URL);
        console.log("\n=========== Verifying L2 Contract Bytecode ===========\n");

        {
            console.log("Checking ExchangeRateProvider contracts...\n");
            address exchangeRateProviderImpl = readImplAddress(OP.L2_EXCHANGE_RATE_PROVIDER);
            console.log("ExchangeRateProvider impl:", exchangeRateProviderImpl);

            bytes memory onchainBytecode = exchangeRateProviderImpl.code;
            bytes memory localBytecode = address(new EtherfiL2ExchangeRateProvider()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(exchangeRateProviderImpl, DEPLOYER_ADDRESS, "")).code;
            localBytecode = OP.L2_EXCHANGE_RATE_PROVIDER.code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        {
            console.log("Checking BucketRateLimiter contracts...\n");
            address rateLimiterImpl = readImplAddress(OP.L2_SYNC_POOL_RATE_LIMITER);
            console.log("BucketRateLimiter impl:", rateLimiterImpl);

            bytes memory onchainBytecode = rateLimiterImpl.code;
            bytes memory localBytecode = address(new BucketRateLimiter()).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(rateLimiterImpl, DEPLOYER_ADDRESS, "")).code;
            localBytecode = OP.L2_SYNC_POOL_RATE_LIMITER.code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        {
            console.log("Checking L2 SyncPool contracts...\n");
            address syncPoolImpl = readImplAddress(OP.L2_SYNC_POOL);
            console.log("SyncPool impl:", syncPoolImpl);

            bytes memory onchainBytecode = syncPoolImpl.code;
            bytes memory localBytecode = address(new L2OPStackSyncPoolETHUpgradeable(OP.L2_ENDPOINT)).code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);

            onchainBytecode = address(new TransparentUpgradeableProxy(syncPoolImpl, DEPLOYER_ADDRESS, "")).code;
            localBytecode = OP.L2_SYNC_POOL.code;
            verifyContractByteCodeMatchFromByteCode(onchainBytecode, localBytecode);
        }

        console.log("\n=========== Verifying L2 Access Control ===========\n");

        adminAddress = address(uint160(uint256(vm.load(OP.L2_SYNC_POOL, _ADMIN_SLOT))));
        assertEq(adminAddress, OP.L2_SYNC_POOL_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(OP.L2_EXCHANGE_RATE_PROVIDER, _ADMIN_SLOT))));
        assertEq(adminAddress, OP.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN);
        adminAddress = address(uint160(uint256(vm.load(OP.L2_SYNC_POOL_RATE_LIMITER, _ADMIN_SLOT))));
        assertEq(adminAddress, OP.L2_SYNC_POOL_RATE_LIMITER_PROXY_ADMIN);

        assertEq(ProxyAdmin(OP.L2_SYNC_POOL_PROXY_ADMIN).owner(), OP.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(ProxyAdmin(OP.L2_EXCHANGE_RATE_PROVIDER_PROXY_ADMIN).owner(), OP.L2_CONTRACT_CONTROLLER_SAFE);
        assertEq(ProxyAdmin(OP.L2_SYNC_POOL_RATE_LIMITER_PROXY_ADMIN).owner(), OP.L2_CONTRACT_CONTROLLER_SAFE);

        console.log("L2 access control verified successfully\n");
        console.log("All verifications passed for OP");
    }
}
