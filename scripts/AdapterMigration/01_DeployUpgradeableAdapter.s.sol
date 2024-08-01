// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import "../../contracts/EtherFiOFTAdapterUpgradeable.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
contract DeployUpgradeableOFTAdapter is Script, Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;
    
    address public adapterProxy;
    EnforcedOptionParam[] public enforcedOptions;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);
        address adapterImpl = new EtherFiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT);
        EtherFiOFTAdapterUpgradeable adapter = EtherFiOFTAdapterUpgradeable(address(
            new TransparentUpgradeableProxy(
                address(upgradeableAdapter),
                L1_CONTRACT_CONTROLLER,
                abi.encodeWithSelector( // delegate and owner stay with the deployer for now
                    EtherFiOFTAdapterUpgradeable.initialize.selector, scriptDeployer, scriptDeployer
                )
            )));

        console.log("Adapter Deployed at: ", adapterProxy);

        address owner = upgradeableAdapter.owner();
        console.log("Owner: ", owner);
        
        console.log("Setting L2s as peers...");
        for (uint256 i = 0; i < L2s.length; i++) {
            upgradeableAdapter.setPeer(L2s[i].L2_EID, _toBytes32(L2s[i].L2_OFT));
        }

        console.log("Setting DVN config for each L2...");
        for (uint256 i = 0; i < L2s.length; i++) {
            _setMainnetDVN(L2s[i].L2_EID);
        }

        console.log("Configuring enforced options...");
        for (uint256 i = 0; i < L2s.length; i++) {
            _appendEnforcedOptions(L2s[i].L2_EID);
        }
        upgradeableAdapter.setEnforcedOptions(enforcedOptions);

        console.log("Transfering ownership to the gnosis...");
        upgradeableAdapter.transferOwnership(L1_CONTRACT_CONTROLLER);
        upgradeableAdapter.setDelegate(L1_CONTRACT_CONTROLLER);

        vm.stopBroadcast();
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
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
    }
}
