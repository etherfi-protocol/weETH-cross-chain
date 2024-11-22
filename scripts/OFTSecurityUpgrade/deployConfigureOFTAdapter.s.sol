// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../../utils/L2Constants.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/LayerZeroHelpers.sol";

contract DeployConfigureNewOFTAdapter is Script, Constants, GnosisHelpers, LayerZeroHelpers {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    RateLimiter.RateLimitConfig[] public rateLimitConfigs;

    function run() public {
    
        vm.startBroadcast();

        // deploy new OFT Adapter contract
        // address newOFTAdapterImpl = address(new EtherfiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT));
        address newOFTAdapterImpl = L1_OFT_ADAPTER_NEW_IMPL;

        // generate the timelock transactio to upgrade the OFT Adapter contract
        string memory scheduleOFTAdapterUpgrade = _getGnosisHeader("1");
        string memory executeOFTAdapterUpgrade = _getGnosisHeader("1");

        // data to initialize the contract during the upgrade
        bytes memory initializationData = abi.encodeWithSignature("initialize(address,address)", L1_CONTRACT_CONTROLLER, L1_CONTRACT_CONTROLLER);
        bytes memory initializationTransaction = abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", L1_OFT_ADAPTER, newOFTAdapterImpl, initializationData);

        // generate timelock schedule and execute transaction
        scheduleOFTAdapterUpgrade = string.concat(scheduleOFTAdapterUpgrade, _getTimelockScheduleTransaction(L1_OFT_ADAPTER_PROXY_ADMIN, initializationTransaction, true));
        executeOFTAdapterUpgrade = string.concat(executeOFTAdapterUpgrade, _getTimelockExecuteTransaction(L1_OFT_ADAPTER_PROXY_ADMIN, initializationTransaction, true));
        vm.writeJson(scheduleOFTAdapterUpgrade, "./output/schedule-oft-adapter-upgrade.json");
        vm.writeJson(executeOFTAdapterUpgrade, "./output/execute-oft-adapter-upgrade.json");

        // generate contract controller transactions to configure new security features {set pauser/unpauser, set rate limits}
        string memory securityUpgradeJson = _getGnosisHeader("1");

        string memory oftAdapter = iToHex(abi.encodePacked(L1_OFT_ADAPTER));
        string memory setPauserTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", PAUSER_ROLE, PAUSER_EOA)), false);
        string memory setUnpauserTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", UNPAUSER_ROLE, L1_CONTRACT_CONTROLLER)), false);

        // set rate limits transactions
        for (uint256 i = 0; i < L2s.length; i++) {
            rateLimitConfigs.push(_getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
        }
        string memory setOutboundRateLimitTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), false);
        string memory setInboundRateLimitTransaction = _getGnosisTransaction(oftAdapter, iToHex(abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs)), true);

        // generate gnosis transaction bundle
        securityUpgradeJson = string.concat(securityUpgradeJson, setPauserTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setUnpauserTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setOutboundRateLimitTransaction);
        securityUpgradeJson = string.concat(securityUpgradeJson, setInboundRateLimitTransaction);
        vm.writeJson(securityUpgradeJson, "./output/configure-mainnet-security.json");
    }
}
