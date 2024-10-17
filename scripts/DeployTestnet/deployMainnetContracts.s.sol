// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

contract DeployOFTScript is Script {

    address constant sepoliaGnosis = 0x05b0f5a18AA3705dFf391f87c4BdD69eA6b8f80B;

    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);


        
    }

}
