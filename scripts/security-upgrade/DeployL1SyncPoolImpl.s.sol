// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "../../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../../utils/L2Constants.sol";

// Deploys a new EtherfiL1SyncPoolETH implementation via CREATE2.
// The proxy upgrade is handled by a separate script outside this repo.
//
// forge script scripts/native-minting-deployment/DeployL1SyncPoolImpl.s.sol:DeployL1SyncPoolImpl --evm-version "shanghai" --slow --ledger --verify --rpc-url $ETH_RPC --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
contract DeployL1SyncPoolImpl is Script, L2Constants {
    address constant ROLE_REGISTRY = 0x62247D29B4B9BECf4BB73E0c722cf6445cfC7cE9;

    function run() public {
        vm.startBroadcast(DEPLOYER_ADDRESS);

        address impl = address(
            new EtherfiL1SyncPoolETH{salt: bytes32(bytes20(hex"c6997994314a62143a923fdd61c9a11b068d8092"))}(L1_ENDPOINT, ROLE_REGISTRY)
        );

        console.log("EtherfiL1SyncPoolETH implementation deployed at:", impl);

        vm.stopBroadcast();
    }
}
