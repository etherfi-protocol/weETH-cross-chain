// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "../../contracts/MintableOFTUpgradeable.sol";
import "../../contracts/EtherFiOFTAdapterUpgradeable.sol";
import "../../utils/LiquidAssetsConstants.sol";
import "../../utils/LayerZeroHelpers.sol";

// Deploys and configures an OFT on scroll for a liquid asset
contract DeployOFT is Script, LiquidConstants, LayerZeroHelpers {
    using OptionsBuilder for bytes;
    
    EnforcedOptionParam[] public enforcedOptions;


    /*//////////////////////////////////////////////////////////////
                    Current Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    address constant DEPLOYMENT_OFT_ADAPTER = address(0x0);
    address constant DEPLOYMENT_OFT = address(0x0);

    /*//////////////////////////////////////////////////////////////
                
    //////////////////////////////////////////////////////////////*/

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        EtherFiOFTAdapterUpgradeable oftAdapter = EtherFiOFTAdapterUpgradeable(DEPLOYMENT_OFT_ADAPTER);

        vm.startBroadcast(privateKey);

        console.log("Setting configs...");

        oftAdapter.setPeer(SCROLL_EID, _toBytes32(DEPLOYMENT_OFT));

        _setDVN(L1_DVN[0], L1_DVN[1]);
        _appendEnforcedOptions(SCROLL_EID);

        oftAdapter.setEnforcedOptions(enforcedOptions);

        console.log("Transferring permissions...");

        // setting the contract controller as the delegate
        oftAdapter.setDelegate(L1_CONTRACT_CONTROLLER);
        
        // transfer ownership to the contract controller
        oftAdapter.transferOwnership(L1_CONTRACT_CONTROLLER);
        
        vm.stopBroadcast();
    }

    // Configures the deployment chain's DVN for the given destination chain
    function _setDVN(address lzDvn, address nethermindDvn) internal {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);

        // The DVN arrays are sorted in ascending order (enforced by requires statements in the layerzer endpoint contract)
        if (lzDvn > nethermindDvn) {
            requiredDVNs[0] = nethermindDvn;
            requiredDVNs[1] = lzDvn;
        } else {
            requiredDVNs[0] = lzDvn;
            requiredDVNs[1] = nethermindDvn;
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(SCROLL_EID, 2, abi.encode(ulnConfig));

        ILayerZeroEndpointV2(L1_LZ_ENDPOINT).setConfig(DEPLOYMENT_OFT_ADAPTER, L1_SEND_302, params);
        ILayerZeroEndpointV2(L1_LZ_ENDPOINT).setConfig(DEPLOYMENT_OFT_ADAPTER, L1_RECEIVE_302, params);
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
