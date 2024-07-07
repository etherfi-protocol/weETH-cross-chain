// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../utils/Constants.sol";

contract SetRateLimits is Script, Constants {
    RateLimiter.RateLimitConfig[] public deploymentRateLimitConfigs;

    function run() public {
        address scriptDeployer;
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        // Address of the WEETH token
        MintableOFTUpgradeable oft = new MintableOFTUpgradeable(DEPLOYMENT_OFT);

        // Set rate limits for L1
        deploymentRateLimitConfigs.push(_getProdRateLimitConfig(L1_EID));

        // Iterate over each L2 and get the rate limit config
        for (uint256 i = 0; i < L2s.length; i++) {
            deploymentRateLimitConfigs.push(_getProdRateLimitConfig(L2s[i].L2_EID));
        }

        oft.setRateLimits(deploymentRateLimitConfigs);
    }

    function _getProdRateLimitConfig(uint32 dstEId) internal pure returns (RateLimiter.RateLimitConfig memory) {
       return RateLimiter.RateLimitConfig({ 
        dstEid: dstEId,
        limit: 200 ether,
        window: 4 hours
       });
    }
}
