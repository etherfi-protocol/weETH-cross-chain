// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import {EtherfiOFTAdapterUpgradeable} from "../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../utils/L2Constants.sol";
import "../utils/LayerZeroHelpers.sol";

// forge script scripts/deploy-isolated-adapter.s.sol:DeployIsolatedAdapter --evm-version "shanghai" --via-ir --verify --slow --rpc-url $ETH_RPC --ledger
contract DeployIsolatedAdapter is Script, L2Constants {
    using OptionsBuilder for bytes;
    
    EnforcedOptionParam[] public enforcedOptions;
    address public adapterProxy;

    uint32 public constant ISOLATED_EID = 30325;

    function run() public returns (address) {
        address scriptDeployer = CA_DEPLOYER_ADDRESS;
        console.log("Deployer: ", scriptDeployer);
        vm.startBroadcast();

        address adapterImpl = address(new EtherfiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT));
        EtherfiOFTAdapterUpgradeable adapter = EtherfiOFTAdapterUpgradeable(address(
            new TransparentUpgradeableProxy(
                address(adapterImpl),
                L1_TIMELOCK,
                abi.encodeWithSelector( // delegate and owner stay with the deployer for now
                    EtherfiOFTAdapterUpgradeable.initialize.selector, scriptDeployer, scriptDeployer
                )
            ))
        );
    
        adapterProxy = address(adapter);
        console.log("Adapter Deployed at: ", adapterProxy);

        address proxyAdminAddress = address(uint160(uint256(vm.load(address(adapter), 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))));
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        console.log("Proxy Admin Owner: ", proxyAdmin.owner());

        console.log("Setting DVN config for isolated chain");
        _setMainnetDVN(ISOLATED_EID);

        console.log("Configuring enforced options for isolated chain...");
        _appendEnforcedOptions(ISOLATED_EID);

        IOAppOptionsType3(adapterProxy).setEnforcedOptions(enforcedOptions);

        vm.stopBroadcast();
        return adapterProxy;
    }

    function _setMainnetDVN(uint32 dstEid) public {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);

        // sorting the DVNs to prevent LZ_ULN_Unsorted() errors
        if (L1_LZ_DVN > L1_NETHERMIND_DVN) {
            requiredDVNs[0] = L1_NETHERMIND_DVN;
            requiredDVNs[1] = L1_LZ_DVN;
        } else {
            requiredDVNs[0] = L1_LZ_DVN;
            requiredDVNs[1] = L1_NETHERMIND_DVN;
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

        ILayerZeroEndpointV2(L1_ENDPOINT).setConfig(adapterProxy, L1_SEND_302, params);
        ILayerZeroEndpointV2(L1_ENDPOINT).setConfig(adapterProxy, L1_RECEIVE_302, params);
    }

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
