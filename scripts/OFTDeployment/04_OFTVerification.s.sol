// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/L2Constants.sol";
import "../ContractCodeChecker.s.sol";

// forge script scripts/OFTDeployment/04_OFTVerification.s.sol:verifyOFT --evm-version "paris" --via-ir
contract verifyOFT is ContractCodeChecker, Script, L2Constants, Test {

    function run() public {
        vm.createSelectFork(DEPLOYMENT_RPC_URL);

        console2.log("#1. Verification of [OFT implementation] bytecode...");
        EtherfiOFTUpgradeable tmpOFT = new EtherfiOFTUpgradeable(DEPLOYMENT_LZ_ENDPOINT);
        verifyContractByteCodeMatch(DEPLOYMENT_OFT_IMPL, address(tmpOFT));

        console2.log("#2. Verification of [OFT proxy] bytecode...");
        address INITIAL_OWNER = DEPLOYER_ADDRESS;
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

        assertEq(ProxyAdmin(DEPLOYMENT_PROXY_ADMIN_CONTRACT).owner(), DEPLOYMENT_CONTRACT_CONTROLLER);

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
