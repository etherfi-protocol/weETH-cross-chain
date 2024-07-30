// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../..contracts/EtherFiOFTAdapterUpgradeable.sol";
import "../../utils/Constants.sol";

contract DeployUpgradeableOFTAdapter is Script, Constants {

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        address adapterImpl = address(new EtherFiOFTAdapterUpgradeable(DEPLOYMENT_LZ_ENDPOINT));
        address adapterProxy = address(
            new TransparentUpgradeableProxy(
                adapterImpl,
                L1_CONTRACT_CONTROLLER,
                abi.encodeWithSelector(
                    EtherFiOFTAdapterUpgradeable.initialize.selector, L1_CONTRACT_CONTROLLER
                )
            )
        );
        vm.stopBroadcast();
    }
}