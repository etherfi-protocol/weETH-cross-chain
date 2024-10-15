// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import 
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../contracts/DummyTokenUpgradeable.sol";

import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract L1NativeMintingScript is Script, Constants, LayerZeroHelpers {
    
    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        console.log("Deploying contracts on L1...");
        
        address dummyTokenImpl = address(new DummyTokenUpgradeable(18));
        address dummyTokenProxy = address(
            new TransparentUpgradeableProxy(
                dummyTokenImpl, 
                L1_CONTRACT_CONTROLLER, 
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, DUMMY_TOKEN_NAME, DUMMY_TOKEN_SYMBOL, scriptDeployer
                )
            )
        );

        address scrollReceiverImpl = address(new L1ScrollReceiverETHUpgradeable());
        address scrollReceiverProxy = address(
            new TransparentUpgradeableProxy(
                scrollReceiverImpl, 
                L1_CONTRACT_CONTROLLER, 
                abi.encodeWithSelector(
                    L1ScrollReceiverETHUpgradeable.initialize.selector, L1_SYNC_POOL, L1_MESSENGER, L1_CONTRACT_CONTROLLER
                )
            )
        );

        console.log("DummyToken deployed at: ", dummyTokenProxy);
    }
}
