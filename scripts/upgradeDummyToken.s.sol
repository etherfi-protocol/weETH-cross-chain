// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../contracts/DummyTokenUpgradeable.sol";

contract UpgradeDummyToken is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        console.log("UpgradeDummyToken script is running...");

        address implementation = address(new DummyTokenUpgradeable(18));

        console.log("New DummyTokenUpgradeable implementation address: %s", implementation);
        vm.stopBroadcast();
    }
}