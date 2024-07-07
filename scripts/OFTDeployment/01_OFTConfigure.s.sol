// SPDX-License-Identifier: UNLICENSEDde
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../utils/Constants.sol";

struct OFTDeployment {
    address adminAddress;
    address implementationAddress;
    address proxyAddress;
    MintableOFTUpgradeable tokenContract;
}

contract DeployOFTScript is Script, Constants {
    using OptionsBuilder for bytes;

    address scriptDeployer;
    OFTDeployment oftDeployment;
    RateLimiter.RateLimitConfig[] public rateLimitConfigs;
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

        oftDeployment.implementationAddress = address(new MintableOFTUpgradeable{salt: SALT}(DEPLOYMENT_LZ_ENDPOINT));
        oftDeployment.proxyAddress = address(
            new TransparentUpgradeableProxy{salt: SALT}(
                oftDeployment.implementationAddress,
                scriptDeployer,
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, scriptDeployer
                )
            )
        );

        oftDeployment.tokenContract = MintableOFTUpgradeable(oftDeployment.proxyAddress);

        console.log("OFT proxy", oftDeployment.proxyAddress);
        console.log("OFT implementation", oftDeployment.implementationAddress);
    }

    function configureRateLimits() internal {
        console.log("Configuring rate limits...");
        // Individual rate limits must be set for each chain

        // Set rate limits for L1
        rateLimitConfigs.push(_getRateLimitConfig(L1_EID));

        // Iterate over each L2 and get the rate limit config
        for (uint256 i = 0; i < L2s.length; i++) {
            rateLimitConfigs.push(_getRateLimitConfig(L2s[i].L2_EID));
        }

        oftDeployment.tokenContract.setRateLimits(rateLimitConfigs);
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

    // Helper function to convert an address to bytes32
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Configures the deployment chain's DVN for the given destination chain
    function _setDVN(uint32 dstEid) internal {
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
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));

        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_SEND_LID_302, params);

        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(oftDeployment.proxyAddress, DEPLOYMENT_RECEIVE_LIB_302, params);
    }

    // Gets the rate limit config for this destination chain
    function _getRateLimitConfig(uint32 dstEId) internal pure returns (RateLimiter.RateLimitConfig memory) {
       return RateLimiter.RateLimitConfig({ 
        dstEid: dstEId,
        // standby rate limits till we are ready to go live
        limit: 0.0001 ether,
        window: 1 minutes
       });
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
