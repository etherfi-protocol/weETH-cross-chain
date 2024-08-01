// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";

import "../contracts/MigrationOFT.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract OFTMigrationUnitTests is Test, Constants, LayerZeroHelpers {

    function test_SendNewAdapterToL2s() public {
        // TODO: deploy a test adatper to mainnet add fork test for sends: new adapter -> L2s
    }
    
    // Send a migration message from arb to mainnet from deployed test contract
    function test_MigrationSend() public {
        vm.createSelectFork(vm.envString("ARB_RPC"));
        MigrationOFT migrationOFT = MigrationOFT(DEPLOYMENT_OFT);

        // ensure that the arb gnosis has sufficient funds for cross chain send
        startHoax(DEPLOYMENT_CONTRACT_CONTROLLER);

        uint256 fee = migrationOFT.quoteMigrationMessage(10 ether);
        migrationOFT.sendMigrationMessage{value: fee}(10 ether);

        fee = migrationOFT.quoteMigrationMessage(70_000 ether);
        migrationOFT.sendMigrationMessage{value: fee}(70_000 ether);
    }


    


    


}