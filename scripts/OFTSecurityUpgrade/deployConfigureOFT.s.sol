// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/L2Constants.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/LayerZeroHelpers.sol";

import "../../contracts/PairwiseRateLimiter.sol";


// forge script scripts/OFTSecurityUpgrade/deployConfigureOFT.s.sol:DeployConfigureNewOFT
contract DeployConfigureNewOFT is Script, Constants, GnosisHelpers, LayerZeroHelpers {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                    Current Deployment Parameter 
    //////////////////////////////////////////////////////////////*/

    // contracts have already been deployed
    // ConfigPerL2 currentDeploymentChain = ZKSYNC;

    /*//////////////////////////////////////////////////////////////
                
    //////////////////////////////////////////////////////////////*/

    function run() public {
        
        // contract has already been deployed 
        // vm.createSelectFork(currentDeploymentChain.RPC_URL);
        // vm.startBroadcast();

        // deploy new OFT contract
        // address newOFTImpl = address(new EtherfiOFTUpgradeable(currentDeploymentChain.L2_ENDPOINT));

        for (uint256 i = 0; i < L2s.length; i++) {

            ConfigPerL2 memory currentDeploymentChain = L2s[i];

            // generate transactions for this chain {upgrade OFT contract, set pauser, set unpauser}
            string memory securityUpgradeJson = _getGnosisHeader(currentDeploymentChain.CHAIN_ID);

            // transaction targets addresses
            string memory oftToken = iToHex(abi.encodePacked(currentDeploymentChain.L2_OFT));
            string memory oftProxyAdmin = iToHex(abi.encodePacked(currentDeploymentChain.L2_OFT_PROXY_ADMIN));

            // transaction data
            string memory upgradeTransaction = _getGnosisTransaction(oftProxyAdmin, iToHex(abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", currentDeploymentChain.L2_OFT, currentDeploymentChain.L2_OFT_NEW_IMPL, "")), false);
            string memory setPauserTransaction = _getGnosisTransaction(oftToken, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", PAUSER_ROLE, PAUSER_EOA)), false);
            string memory setUnpauserTransaction = _getGnosisTransaction(oftToken, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", UNPAUSER_ROLE, currentDeploymentChain.L2_CONTRACT_CONTROLLER_SAFE)), false);

            PairwiseRateLimiter.RateLimitConfig[] memory rateLimitConfigs = new PairwiseRateLimiter.RateLimitConfig[](L2s.length);

            // Set rate limits transactions
            for (uint256 j = 0; j < L2s.length; j++) {
                if (L2s[j].L2_EID == currentDeploymentChain.L2_EID) {
                    rateLimitConfigs[j] = _getRateLimitConfig(L1_EID, LIMIT, WINDOW);
                } else {
                    rateLimitConfigs[j] = _getRateLimitConfig(L2s[j].L2_EID, LIMIT, WINDOW);
                }
            }
            
            string memory setOutboundRateLimitTransaction = _getGnosisTransaction(oftToken, iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), false);
            string memory setInboundRateLimitTransaction = _getGnosisTransaction(oftToken, iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), true);

            // generate gnosis transaction file
            securityUpgradeJson = string.concat(securityUpgradeJson, upgradeTransaction);
            securityUpgradeJson = string.concat(securityUpgradeJson, setPauserTransaction);
            securityUpgradeJson = string.concat(securityUpgradeJson, setUnpauserTransaction);
            securityUpgradeJson = string.concat(securityUpgradeJson, setOutboundRateLimitTransaction);
            securityUpgradeJson = string.concat(securityUpgradeJson, setInboundRateLimitTransaction);
            vm.writeJson(securityUpgradeJson, string.concat("./output/security-upgrade-", currentDeploymentChain.NAME, ".json"));
        }
    }
}
