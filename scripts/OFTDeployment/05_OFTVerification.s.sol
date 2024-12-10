// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/Constants.sol";

// forge script scripts/OFTDeployment/05_OFTVerification.s.sol:verifyOFT --evm-version "paris"
contract verifyOFT is Script, Constants, Test {
    function run() public {

        vm.createSelectFork(DEPLOYMENT_RPC_URL);

        console2.log("Verification of OFT implementation bytecode...\n");
        EtherfiOFTUpgradeable tmpOFT = new EtherfiOFTUpgradeable(DEPLOYMENT_LZ_ENDPOINT);
        bytes memory localBytecode = address(tmpOFT).code;
        bytes memory onchainRuntimeBytecode = DEPLOYMENT_OFT_IMPL.code;
        compareBytes(localBytecode, onchainRuntimeBytecode);

        console2.log("Verification of OFT proxy bytecode...\n");
        TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(
            DEPLOYMENT_OFT_IMPL, 
            DEPLOYER_ADDRESS, 
            abi.encodeWithSelector(
            EtherfiOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, DEPLOYER_ADDRESS)
        );
        localBytecode = address(tmpProxy).code;
        onchainRuntimeBytecode = DEPLOYMENT_OFT.code;
        compareBytes(localBytecode, onchainRuntimeBytecode);

        // below the expected roles are verified; see notion for documentation on expected roles
        // https://www.notion.so/etherfi/weETH-Cross-Chain-L2-Roles-11ab09527c4380148ed5ec6a4f869677
        console2.log("Asserting all roles are correct..\n");

        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(DEPLOYMENT_OFT);
        LZEndpoint endpoint = LZEndpoint(DEPLOYMENT_LZ_ENDPOINT);

        assertEq(ProxyAdmin(0xE917Fad11ca0d835d3C8d960906195a641320cd7).owner(), DEPLOYMENT_CONTRACT_CONTROLLER);

        assertEq(oft.owner(), DEPLOYMENT_CONTRACT_CONTROLLER);
        assertTrue(oft.hasRole(oft.PAUSER_ROLE(), PAUSER_EOA));
        assertTrue(oft.hasRole(oft.UNPAUSER_ROLE(), DEPLOYMENT_CONTRACT_CONTROLLER));
        assertTrue(oft.hasRole(oft.DEFAULT_ADMIN_ROLE(), DEPLOYMENT_CONTRACT_CONTROLLER));
        assertFalse(oft.hasRole(oft.DEFAULT_ADMIN_ROLE(), DEPLOYER_ADDRESS));

        assertEq(endpoint.delegates(DEPLOYMENT_OFT), DEPLOYMENT_CONTRACT_CONTROLLER);
    
        console2.log("All roles are correct!\n");
    }

    function compareBytes(bytes memory a, bytes memory b) internal pure {

        if (keccak256(a) == keccak256(b)) {
            console2.log("Runtime bytecode exact match!\n");
        } else if (a.length == b.length) {
            console2.log("Bytecode length match!\n");
        } else {
            console2.log("XXXX Bytecode doesn't match XXXX\n");
        }
    }
}

// allows us to interface with the delegates function that isn't defined in the ILayerZeroEndpointV2 interface
interface LZEndpoint {
    function delegates(address) external view returns (address);
}
