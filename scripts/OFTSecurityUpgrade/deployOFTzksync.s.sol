// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";


import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";

import "../../utils/Constants.sol";

// commands to run
// curl -L https://raw.githubusercontent.com/matter-labs/foundry-zksync/main/install-foundry-zksync | bash
// foundryup-zksync
// forge script scripts/OFTSecurityUpgrade/deployOFTzksync.s.sol:deployOFTzksync --evm-version shanghai --zksync
contract deployOFTzksync is Script, Constants {
    function run() public {

        ConfigPerL2 memory currentDeploymentChain = ZKSYNC;
        vm.createSelectFork(currentDeploymentChain.RPC_URL);

        // Create a temporary instance to get expected local bytecode
        new EtherfiOFTUpgradeable(currentDeploymentChain.L2_ENDPOINT);

    }
}
