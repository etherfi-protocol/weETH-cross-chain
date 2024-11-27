// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";


import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";

import "../../utils/Constants.sol";

// forge script scripts/OFTSecurityUpgrade/verityDeploymentBytecode.s.sol:verifyOFTUpgradeBytecode --sig "run(string)" "shanghai" --evm-version shanghai
// forge script scripts/OFTSecurityUpgrade/verityDeploymentBytecode.s.sol:verifyOFTUpgradeBytecode --sig "run(string)" "paris" --evm-version paris
contract verifyOFTUpgradeBytecode is Script, Constants {
    function run(string memory evmVersion) public {
        console.log("\nRunning verification with EVM version:", evmVersion);

        for (uint256 i = 0; i < L2s.length; i++) {

            ConfigPerL2 memory currentDeploymentChain = L2s[i];
            // Skip chains that don't use the specified EVM version
            if (keccak256(abi.encodePacked(getChainEvmVersion(currentDeploymentChain.NAME))) != 
                keccak256(abi.encodePacked(evmVersion))) {
                continue;
            }
            vm.createSelectFork(currentDeploymentChain.RPC_URL);

            // Create a temporary instance to get expected local bytecode
            EtherfiOFTUpgradeable tmp = new EtherfiOFTUpgradeable(currentDeploymentChain.L2_ENDPOINT);
            bytes memory localBytecode = address(tmp).code;

            // compared to deployed address
            bytes memory onchainRuntimeBytecode = currentDeploymentChain.L2_OFT_NEW_IMPL.code;

            bool runtimeMatches = keccak256(localBytecode) == keccak256(onchainRuntimeBytecode);
        
            console.log(currentDeploymentChain.NAME);
            console2.log("=== Contract Verification Results ===");
            console2.log("Contract address:", currentDeploymentChain.L2_OFT_NEW_IMPL);
        
            if (runtimeMatches) {
                console2.log("Runtime bytecode matches!\n");
            } else {
                console2.log("XXXX Bytecode doesn't match XXXX\n");
            }
        }

        // OFTAdapter was deployed with paris hence we verify it as well on the paris run
        if (keccak256(abi.encodePacked(evmVersion)) == keccak256(abi.encodePacked("paris"))) {
            vm.createSelectFork(L1_RPC_URL);
            EtherfiOFTAdapterUpgradeable tmp = new EtherfiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT);
            bytes memory localBytecode = address(tmp).code;

            // compared to deployed address
            bytes memory onchainRuntimeBytecode = L1_OFT_ADAPTER_NEW_IMPL.code;

            bool runtimeMatches = keccak256(localBytecode) == keccak256(onchainRuntimeBytecode);
        
            console.log("mainnet");
            console2.log("=== Contract Verification Results ===");
            console2.log("Contract address:", L1_OFT_ADAPTER_NEW_IMPL);
        
            if (runtimeMatches) {
                console2.log("Runtime bytecode matches!\n");
            } else {
                console2.log("XXXX Bytecode doesn't match XXXX\n");
            }

        }
    }

    function getChainEvmVersion(string memory chainName) internal pure returns (string memory) {
        // Shanghai EVM chains
        if (
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("blast")) ||
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("mode")) ||
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("base")) ||
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("op")) ||
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("scroll"))
        ) {
            return "shanghai";
        }
        // Paris EVM chains
        else if (
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("linea")) ||
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("bnb"))
        ) {
            return "paris";
        } 
        // zksync custom
        else if (
            keccak256(abi.encodePacked(chainName)) == keccak256(abi.encodePacked("zksync"))
        ) {
            return "zksync-shanghai";
        } else {
            return "unknown";
        }
    }
}
