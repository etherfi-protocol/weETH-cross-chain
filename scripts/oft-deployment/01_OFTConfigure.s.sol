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

// forge script scripts/oft-deployment/01_OFTConfigure.s.sol:DeployOFTScript --via-ir  --ledger --sender 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150 --rpc-url "deployment rpc"  --verify --etherscan-api-key "etherscan key"
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
        // Per-pathway rate limits: one config per peer, sourced from the registry
        // (DEPLOYMENT_PEER_LIMITS / DEPLOYMENT_PEER_WINDOWS). Values may differ per
        // chain; for the current peers they are all 1000 weETH / 4h.

        if (DEPLOYMENT_PEER_EIDS.length > 0) {
            for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
                rateLimitConfigs.push(LayerZeroHelpers._getRateLimitConfig(DEPLOYMENT_PEER_EIDS[i], DEPLOYMENT_PEER_LIMITS[i], DEPLOYMENT_PEER_WINDOWS[i]));
            }
        } else {
            rateLimitConfigs.push(LayerZeroHelpers._getRateLimitConfig(L1_EID, LIMIT, WINDOW));
            for (uint256 i = 0; i < L2s.length; i++) {
                rateLimitConfigs.push(LayerZeroHelpers._getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
            }
        }

        oftDeployment.tokenContract.setInboundRateLimits(rateLimitConfigs);
        oftDeployment.tokenContract.setOutboundRateLimits(rateLimitConfigs);
    }

    function configurePeer() internal {
        console.log("Configuring peers...");

        if (DEPLOYMENT_PEER_EIDS.length > 0) {
            // Registry allow-list (the only peers this chain bridges with)
            for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
                oftDeployment.tokenContract.setPeer(DEPLOYMENT_PEER_EIDS[i], LayerZeroHelpers._toBytes32(DEPLOYMENT_PEER_OFTS[i]));
            }
        } else {
            oftDeployment.tokenContract.setPeer(L1_EID, LayerZeroHelpers._toBytes32(L1_OFT_ADAPTER));
            for (uint256 i = 0; i < L2s.length; i++) {
                oftDeployment.tokenContract.setPeer(L2s[i].L2_EID, LayerZeroHelpers._toBytes32(L2s[i].L2_OFT));
            }
        }
    }

    function configureDVN() internal {
        console.log("Configuring DVNs...");
        // `setConfig` must be called for each peer in the mesh network

        if (DEPLOYMENT_PEER_EIDS.length > 0) {
            for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) _setDVN(DEPLOYMENT_PEER_EIDS[i]);
        } else {
            _setDVN(L1_EID);
            for (uint256 i = 0; i < L2s.length; i++) _setDVN(L2s[i].L2_EID);
        }
    }

    function configureEnforcedOptions() internal {
        console.log("Configuring enforced options...");

        if (DEPLOYMENT_PEER_EIDS.length > 0) {
            for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) _appendEnforcedOptions(DEPLOYMENT_PEER_EIDS[i]);
        } else {
            _appendEnforcedOptions(L1_EID);
            for (uint256 i = 0; i < L2s.length; i++) _appendEnforcedOptions(L2s[i].L2_EID);
        }

        oftDeployment.tokenContract.setEnforcedOptions(enforcedOptions);
    }

    // Configures the deployment chain's DVN for the given destination chain
    function _setDVN(uint32 dstEid) public {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        // DEPLOYMENT_DVNS is pre-sorted ascending by _loadTarget() — no runtime sort needed.
        address[] memory requiredDVNs = new address[](4);
        for (uint256 i = 0; i < 4; i++) requiredDVNs[i] = DEPLOYMENT_DVNS[i];

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 45,
            requiredDVNCount: 4,
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
