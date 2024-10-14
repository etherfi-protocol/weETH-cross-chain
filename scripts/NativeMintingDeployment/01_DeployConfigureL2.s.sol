// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../utils/Constants.sol";


contract L1NativeMintingScript is Script, Constants {
    ConfigPerL2 public DEPLOYMENT_L2;

    function run() public {
        DEPLOYMENT_L2 = SCROLL;

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        console.log("Deploying contracts on L2...");

        // Deploy Sync Pool
        address syncPoolImp = address(new L2ScrollSyncPoolETHUpgradeable(DEPLOYMENT_L2.L2_ENDPOINT));
        

        address bucketRateLimiterImp = address(new BucketRateLimiter());
        UUPSProxy proxy = new UUPSProxy(bucketRateLimiterImp, abi.encodeWithSelector(BucketRateLimiter.initialize.selector));
        BucketRateLimiter bucketRateLimiter = BucketRateLimiter(address(proxy));

    }
}
