// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract SetRateLimits is Script, Constants, LayerZeroHelpers {
    RateLimiter.RateLimitConfig[] public deploymentRateLimitConfigs;

    function run() public {
        address scriptDeployer;
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        // Address of the WEETH token
        MintableOFTUpgradeable oft = new MintableOFTUpgradeable(DEPLOYMENT_OFT);

        // Set rate limits for L1
        deploymentRateLimitConfigs.push(_getRateLimitConfig(L1_EID, LIMIT, WINDOW));

        // Iterate over each L2 and get the rate limit config
        for (uint256 i = 0; i < L2s.length; i++) {
            deploymentRateLimitConfigs.push(_getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
        }

        oft.setRateLimits(deploymentRateLimitConfigs);
    }
}
