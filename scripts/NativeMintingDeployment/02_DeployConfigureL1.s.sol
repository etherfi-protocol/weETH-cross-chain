// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../contracts/DummyTokenUpgradeable.sol";

import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract L1NativeMintingScript is Script, Constants, LayerZeroHelpers {

    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        console.log("Deploying contracts on L1...");

        address dummyTokenImp = address(new DummyTokenUpgradeable(18));
        address dummyTokenProxy = address(
            new TransparentUpgradeableProxy(
                dummyTokenImp, 
                scriptDeployer, 
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, "Scroll Dummy ETH", "scrollETH", scriptDeployer
                )
            )
        );

        console.log("DummyToken deployed at: ", dummyTokenProxy);
        
    }
}
