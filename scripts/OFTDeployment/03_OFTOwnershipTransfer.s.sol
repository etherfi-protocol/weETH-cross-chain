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

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../utils/L2Constants.sol";

contract OFTOwnershipTransfer is Script, Constants {
    using OptionsBuilder for bytes;
    address scriptDeployer;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        MintableOFTUpgradeable oft = MintableOFTUpgradeable(DEPLOYMENT_OFT);
        ProxyAdmin oftProxyAdmin = ProxyAdmin(DEPLOYMENT_PROXY_ADMIN_CONTRACT);


        address owner = oft.owner();
        console.log("OFT owner: %s", owner);

        // setting the contract controller as the delegate
        oft.setDelegate(DEPLOYMENT_CONTRACT_CONTROLLER);

        // set the contract controller as the default admin
        oft.grantRole(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000), DEPLOYMENT_CONTRACT_CONTROLLER);

        // revoke the script deployer's admin role
        oft.renounceRole(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000), scriptDeployer);
        
        // transfer ownership to the contract controller
        oft.transferOwnership(DEPLOYMENT_CONTRACT_CONTROLLER);

        // transfer ownership of the proxy admin to the contract controller
        oftProxyAdmin.transferOwnership(DEPLOYMENT_CONTRACT_CONTROLLER);

        vm.stopBroadcast();
    }
}
