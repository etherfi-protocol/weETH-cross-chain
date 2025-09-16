// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "../../contracts/PairwiseRateLimiter.sol";

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../../interfaces/ICreate3Deployer.sol";

struct OFTDeployment {
    address adminAddress;
    address implementationAddress;
    address proxyAddress;
    EtherfiOFTUpgradeable tokenContract;
}

// forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript --via-ir  --ledger --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 --rpc-url "deployment rpc"  --verify --etherscan-api-key "etherscan key"
contract DeployOFTScript is Script, L2Constants {
    using OptionsBuilder for bytes;

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    address scriptDeployer;
    OFTDeployment oftDeployment;
    PairwiseRateLimiter.RateLimitConfig[] public rateLimitConfigs;
    EnforcedOptionParam[] public enforcedOptions;

    function run() public {
        scriptDeployer = DEPLOYER_ADDRESS;
        vm.startBroadcast();

        deployOFT();

        configureRateLimits();
        configurePeer();
        configureEnforcedOptions();
        configureDVN();

        vm.stopBroadcast();
    }

    function deployOFT() internal {
        console.log("Deploying OFT contract...");

        bytes memory implCreationCode = abi.encodePacked(type(EtherfiOFTUpgradeable).creationCode, abi.encode(DEPLOYMENT_LZ_ENDPOINT));

        oftDeployment.implementationAddress = CREATE3.deployCreate3(keccak256("EtherfiOFTUpgradeable-impl"), implCreationCode);

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode, 
            abi.encode(oftDeployment.implementationAddress, scriptDeployer, abi.encodeWithSelector(EtherfiOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, scriptDeployer))
        );

        oftDeployment.proxyAddress = CREATE3.deployCreate3(keccak256("EtherfiOFTUpgradeable-proxy"), proxyCreationCode);

        oftDeployment.tokenContract = EtherfiOFTUpgradeable(oftDeployment.proxyAddress);
        require(oftDeployment.proxyAddress == DEPLOYMENT_OFT, "OFT proxy address is not correct");
        require(oftDeployment.implementationAddress == DEPLOYMENT_OFT_IMPL, "OFT implementation address is not correct");

        oftDeployment.proxyAddress = DEPLOYMENT_OFT;
        oftDeployment.tokenContract = EtherfiOFTUpgradeable(oftDeployment.proxyAddress);

        address[] memory controller = new address[](1);
        controller[0] = DEPLOYMENT_CONTRACT_CONTROLLER;
        if(DEPLOYMENT_CONTRACT_CONTROLLER == address(0)) {
            revert("DEPLOYMENT_CONTRACT_CONTROLLER is not set");
        }

        bytes memory timelockCreationCode = abi.encodePacked(
            type(EtherFiTimelock).creationCode, 
            abi.encode(3 days, controller, controller, address(0))
        );
        address timelockAddress = CREATE3.deployCreate3(keccak256("EtherFiTimelock"), timelockCreationCode);
        require(timelockAddress == L2_TIMELOCK, "Timelock address is not correct");


        console.log("OFT proxy", oftDeployment.proxyAddress);
        console.log("OFT implementation", oftDeployment.implementationAddress);
    }

    function configureRateLimits() internal {
        console.log("Configuring rate limits...");
        // Individual rate limits must be set for each chain

        rateLimitConfigs.push(LayerZeroHelpers._getRateLimitConfig(L1_EID, LIMIT, WINDOW));
        for (uint256 i = 0; i < L2s.length; i++) {
            rateLimitConfigs.push(LayerZeroHelpers._getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
        }

        oftDeployment.tokenContract.setInboundRateLimits(rateLimitConfigs);
        oftDeployment.tokenContract.setOutboundRateLimits(rateLimitConfigs);
    }

    function configurePeer() internal {
        console.log("Configuring peers...");

        // Setting L1 peer
        oftDeployment.tokenContract.setPeer(L1_EID, LayerZeroHelpers._toBytes32(L1_OFT_ADAPTER));

        // Iterating through all existing L2s to set peers 
        for (uint256 i = 0; i < L2s.length; i++) {
            oftDeployment.tokenContract.setPeer(L2s[i].L2_EID, LayerZeroHelpers._toBytes32(L2s[i].L2_OFT));
        }

    }

    function configureDVN() internal {
        console.log("Configuring DVNs...");
        // `setConfig` be called for each other chain in the mesh network

        // Set DVN for L1
        _setDVN(L1_EID);

        // Iterate over each L2 and set the config
        for (uint256 i = 0; i < L2s.length; i++) {
            _setDVN(L2s[i].L2_EID);
        }
    }

    function configureEnforcedOptions() internal {
        console.log("Configuring enforced options...");

        _appendEnforcedOptions(L1_EID);
        for (uint256 i = 0; i < L2s.length; i++) {
            _appendEnforcedOptions(L2s[i].L2_EID);
        }

        oftDeployment.tokenContract.setEnforcedOptions(enforcedOptions);
    }

    // Configures the deployment chain's DVN for the given destination chain
    function _setDVN(uint32 dstEid) public {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);

        // sorting the DVNs to prevent LZ_ULN_Unsorted() errors
        if (DEPLOYMENT_LZ_DVN > DEPLOYMENT_NETHERMIND_DVN) {
            requiredDVNs[0] = DEPLOYMENT_NETHERMIND_DVN;
            requiredDVNs[1] = DEPLOYMENT_LZ_DVN;
        } else {
            requiredDVNs[0] = DEPLOYMENT_LZ_DVN;
            requiredDVNs[1] = DEPLOYMENT_NETHERMIND_DVN;
        }
        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_SEND_LIB_302, params);
        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_RECEIVE_LIB_302, params);
    }

    // Configures the enforced options for the given destination chain
    function _appendEnforcedOptions(uint32 dstEid) internal {
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
    }
}
