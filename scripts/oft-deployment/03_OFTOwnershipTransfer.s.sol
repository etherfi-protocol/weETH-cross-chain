// SPDX-License-Identifier: UNLICENSEDde
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/L2Constants.sol";

// forge script scripts/oft-deployment/03_OFTOwnershipTransfer.s.sol:OFTOwnershipTransfer --rpc-url "deployment rpc" --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 --ledger 
contract OFTOwnershipTransfer is Script, L2Constants {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    using OptionsBuilder for bytes;
    address scriptDeployer;

    function run() public {
        scriptDeployer = DEPLOYER_ADDRESS;
        vm.startBroadcast();

        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(DEPLOYMENT_OFT);
        ProxyAdmin oftProxyAdmin = ProxyAdmin(DEPLOYMENT_PROXY_ADMIN_CONTRACT);


        // setting the contract controller as the delegate
        oft.setDelegate(DEPLOYMENT_CONTRACT_CONTROLLER);

        // granting pauser roles
        oft.setRole(PAUSER_EOA, oft.PAUSER_ROLE(), true);
        oft.setRole(DEPLOYMENT_CONTRACT_CONTROLLER, oft.UNPAUSER_ROLE(), true);
        
        // transfer ownership to the contract controller
        oft.transferOwnership(L2_TIMELOCK);

        // transfer ownership of the proxy admin to the contract controller
        oftProxyAdmin.transferOwnership(L2_TIMELOCK);

        console.log("OFT new owner: %s", oft.owner());
        console.log("OFT proxy admin new owner: %s", oftProxyAdmin.owner());

        vm.stopBroadcast();
        // gpg test
    }
}
