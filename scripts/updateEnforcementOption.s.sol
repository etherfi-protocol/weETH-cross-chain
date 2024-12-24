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
import "../contracts/PairwiseRateLimiter.sol";

import "../contracts/EtherfiOFTUpgradeable.sol";
import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";

// forge script scripts/OFTDeployment/01_OFTConfigure.s.sol:DeployOFTScript --evm-version "paris" --rpc-url "deployment rpc" --ledger --verify --etherscan-api-key "etherscan key"
contract ResetEnforcementOptions is Script, Constants, LayerZeroHelpers {

    function run() public {


    }

    function updateEnforcedOptions(uint32 currentChain) internal {

        EnforcedOptionParam[] memory enforcedOptions;
        enforcedOptions = new EnforcedOptionParam[](2);

        enforcedOptions[0] = EnforcedOptionParam({
            eid: DEPLOYMENT_EID,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: DEPLOYMENT_EID,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        });

    }

    function _appendEnforcedOptions(uint32 dstEid) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        enforcedOptions.push(EnforcedOptionParam(dstEid, 1, options));
        enforcedOptions.push(EnforcedOptionParam(dstEid, 2, options));
    }

}
