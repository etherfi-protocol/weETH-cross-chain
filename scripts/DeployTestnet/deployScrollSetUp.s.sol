// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";

contract DeployOFTScript is Script, L2Constants {

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        address oftImpl = address(new MintableOFTUpgradeable(DEPLOYMENT_LZ_ENDPOINT));
        address oftProxy = address(
            new TransparentUpgradeableProxy(
                oftImpl,
                scriptDeployer,
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, "Scroll weETH", "weETH", scriptDeployer
                )
            )
        );
    }

}
