// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../../utils/Constants.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/LayerZeroHelpers.sol";

contract DeployConfigureNewOFTAdapter is Script, Constants, GnosisHelpers, LayerZeroHelpers {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    RateLimiter.RateLimitConfig[] public rateLimitConfigs;

    function run() public {
        
        // vm.createSelectFork(L1_RPC_URL);
        vm.startBroadcast();

        // deploy new OFT Adapter contract
        address newOFTAdapterImpl = address(new EtherfiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT));

        // generate transactions for this chain {upgrade OFT Adapter contract, set pauser/unpauser, set rate limits}
        string memory securityUpgradeJson = _getGnosisHeader("1");

        // transaction targets addresses 
        string memory oftAdapter = iToHex(abi.encodePacked(L1_OFT_ADAPTER));
        string memory oftAdapterProxyAdmin = iToHex(abi.encodePacked(L1_OFT_ADAPTER_PROXY_ADMIN));

        // data to initialize the contract during the upgrade
        bytes memory initializationData = abi.encodeWithSignature("initialize(address,address)", L1_CONTRACT_CONTROLLER, L1_CONTRACT_CONTROLLER);

        // transaction data
        string memory upgradeTransaction = _getGnosisTransaction(oftAdapterProxyAdmin, iToHex(abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", L1_OFT_ADAPTER_PROXY_ADMIN, newOFTAdapterImpl, initializationData)), false);
        string memory setPauserTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", PAUSER_ROLE, PAUSER_EOA)), false);
        string memory setUnpauserTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", UNPAUSER_ROLE, L1_CONTRACT_CONTROLLER)), false);

        // set rate limits transactions
        for (uint256 i = 0; i < L2s.length; i++) {
            rateLimitConfigs.push(_getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
        }
        string memory setOutboundRateLimitTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), false);
        string memory setInboundRateLimitTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), true);

        // generate gnosis transaction file
        securityUpgradeJson = string.concat(securityUpgradeJson, upgradeTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setPauserTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setUnpauserTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setOutboundRateLimitTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setInboundRateLimitTransaction);
        vm.writeJson(securityUpgradeJson, string.concat("./output/security-upgrade-mainnet.json"));
    }

    

}
