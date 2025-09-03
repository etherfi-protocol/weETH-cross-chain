// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/EtherfiOFTUpgradeable.sol";
import "../utils/L2Constants.sol";
import "../contracts/EtherFiTimelock.sol";
import "./ContractCodeChecker.sol";

// forge script scripts/Verify-Ownership-Transfer.s.sol:verifyTimelock
contract verifyTimelock is ContractCodeChecker, Script, L2Constants, Test {

    function run() public {

        for (uint256 i = 0; i < L2s.length; i++) {
            vm.createSelectFork(L2s[i].RPC_URL);
            console2.log("Verifying timelock on ", L2s[i].NAME, "...");


            address[] memory controller = new address[](1);
            controller[0] = L2s[i].L2_CONTRACT_CONTROLLER_SAFE;

            EtherFiTimelock timelockTest = new EtherFiTimelock(3 days, controller, controller, L2_TIMELOCK);

            console2.log("#1. Verification of deployed timelock bytecode...");
            verifyContractByteCodeMatchFromAddress(L2_TIMELOCK, address(timelockTest));

            console2.log("#2. Asserting all roles are correct on timelock..\n");

            EtherFiTimelock timelock = EtherFiTimelock(payable(L2_TIMELOCK));
            assertEq(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), L2_TIMELOCK), true);
            assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(), L2s[i].L2_CONTRACT_CONTROLLER_SAFE), true);
            assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(), L2s[i].L2_CONTRACT_CONTROLLER_SAFE), true);
            assertEq(timelock.hasRole(timelock.CANCELLER_ROLE(), L2s[i].L2_CONTRACT_CONTROLLER_SAFE), true);

            console2.log("All roles are correct!\n");
        }
    }
}
