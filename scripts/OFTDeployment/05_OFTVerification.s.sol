// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/Constants.sol";
import "../ContractCodeChecker.s.sol";

// forge script scripts/OFTDeployment/05_OFTVerification.s.sol:verifyOFT --evm-version "paris"
contract verifyOFT is ContractCodeChecker, Script, Constants, Test {

    function run() public {
        vm.createSelectFork(DEPLOYMENT_RPC_URL);

        console2.log("#1. Verification of [OFT implementation] bytecode...");
        EtherfiOFTUpgradeable tmpOFT = new EtherfiOFTUpgradeable(DEPLOYMENT_LZ_ENDPOINT);
        verifyContractByteCodeMatch(DEPLOYMENT_OFT_IMPL, address(tmpOFT));

        console2.log("#2. Verification of [OFT proxy] bytecode...");
        address INITIAL_OWNER = 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150;
        TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(
            DEPLOYMENT_OFT_IMPL, 
            INITIAL_OWNER,  
            abi.encodeWithSelector(
            EtherfiOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, DEPLOYER_ADDRESS)
        );
        verifyContractByteCodeMatch(DEPLOYMENT_OFT, address(tmpProxy));

        // below the expected roles are verified; see notion for documentation on expected roles
        // https://www.notion.so/etherfi/weETH-Cross-Chain-L2-Roles-11ab09527c4380148ed5ec6a4f869677
        console2.log("#3. Asserting all roles are correct..\n");

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
}

// allows us to interface with the delegates function that isn't defined in the ILayerZeroEndpointV2 interface
interface LZEndpoint {
    function delegates(address) external view returns (address);
}
