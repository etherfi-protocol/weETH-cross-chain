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


import "../../contracts/EBTCMintableOFTUpgradeable.sol";
import "../../contracts/PairwiseRateLimiter.sol";

import "../../utils/EBTCConstants.sol";
import "../../utils/LayerZeroHelpers.sol";

struct OFTDeployment {
    address adminAddress;
    address implementationAddress;
    address proxyAddress;
    EBTCMintableOFTUpgradeable tokenContract;
}

contract DeployOFTScript is Script, EBTCConstants, LayerZeroHelpers {
    using OptionsBuilder for bytes;

    address scriptDeployer;
    OFTDeployment oftDeployment;
    PairwiseRateLimiter.RateLimitConfig[] public rateLimitConfigs;
    EnforcedOptionParam[] public enforcedOptions;

    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        deployOFT();

        configureRateLimits();
        configurePeer();
        configureEnforcedOptions();
        configureDVN();

        vm.stopBroadcast();
    }

    function deployOFT() internal {
        console.log("Deploying OFT contract...");

        // Create salt for deployment
        bytes32 SALT = keccak256(abi.encodePacked(scriptDeployer, TOKEN_NAME));

        oftDeployment.implementationAddress = address(new EBTCMintableOFTUpgradeable{salt: SALT}(DEPLOYMENT_LZ_ENDPOINT));
        oftDeployment.proxyAddress = address(
            new TransparentUpgradeableProxy{salt: SALT}(
                oftDeployment.implementationAddress,
                scriptDeployer,
                abi.encodeWithSelector(
                    EBTCMintableOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, scriptDeployer
                )
            )
        );

        oftDeployment.tokenContract = EBTCMintableOFTUpgradeable(oftDeployment.proxyAddress);

        console.log("OFT proxy", oftDeployment.proxyAddress);
        console.log("OFT implementation", oftDeployment.implementationAddress);
    }

    function configureRateLimits() internal {
        console.log("Configuring rate limits...");
        // Individual rate limits must be set for each chain

        // setting standby rate limits for L1
        rateLimitConfigs.push(_getRateLimitConfig(L1_EID, LIMIT, WINDOW));

        // Iterate over each L2 and add the standby rate limit config
        for (uint256 i = 0; i < L2s.length; i++) {
            rateLimitConfigs.push(_getRateLimitConfig(L2s[i].L2_EID, LIMIT, WINDOW));
        }

        oftDeployment.tokenContract.setOutboundRateLimits(rateLimitConfigs);
        oftDeployment.tokenContract.setInboundRateLimits(rateLimitConfigs);
    }

    function configurePeer() internal {
        console.log("Configuring peers...");

        // Setting L1 peer
        oftDeployment.tokenContract.setPeer(L1_EID, _toBytes32(L1_OFT_ADAPTER));

        // Iterating through all existing L2s to set peers 
        for (uint256 i = 0; i < L2s.length; i++) {
            oftDeployment.tokenContract.setPeer(L2s[i].L2_EID, _toBytes32(L2s[i].L2_OFT));
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

        params[0] = SetConfigParam(dstEid, 2, _getExpectedUln(DEPLOYMENT_DVN[0], DEPLOYMENT_DVN[1]));

        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_SEND_LID_302, params);
        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_RECEIVE_LIB_302, params);
    }

    // Configures the enforced options for the given destination chain
    function _appendEnforcedOptions(uint32 dstEid) internal {
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
    }
}
