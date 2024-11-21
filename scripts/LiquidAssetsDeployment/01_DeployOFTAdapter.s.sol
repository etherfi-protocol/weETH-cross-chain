// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../../utils/LiquidAssetsConstants.sol";


// Deployment of an OFT adapter for a new native asset. Used in in the LiquidAssetsDeployment flow, but could be used to start a bridge for any asset
contract DeployUpgradeableOFTAdapterLiquid is Script, LiquidConstants {

    /*//////////////////////////////////////////////////////////////
                    Current Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    address constant DEPLOYMENT_ASSET = WEETHS;

    /*//////////////////////////////////////////////////////////////
                
    //////////////////////////////////////////////////////////////*/

    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        address adapterImpl = address(new EtherfiOFTAdapterUpgradeable(DEPLOYMENT_ASSET, L1_LZ_ENDPOINT));
        EtherfiOFTAdapterUpgradeable adapter = EtherfiOFTAdapterUpgradeable(address(
            new TransparentUpgradeableProxy(
                address(adapterImpl),
                L1_CONTRACT_CONTROLLER,
                abi.encodeWithSelector( // delegate and owner stay with the deployer for now
                    EtherfiOFTAdapterUpgradeable.initialize.selector, scriptDeployer, scriptDeployer
                )
            ))
        );

        console.log("Deployed OFT adapter at address: ", address(adapter));
        console.log("For asset: ", adapter.token());
    }
}
