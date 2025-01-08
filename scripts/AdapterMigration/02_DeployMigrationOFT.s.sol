// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/archive/MigrationOFT.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";


contract DeployMigrationOFT is Script, L2Constants {
    using OptionsBuilder for bytes;

    address public migrationOFTAddress;
    EnforcedOptionParam[] public enforcedOptions;
    
    address constant DEPLOYMENT_OFT_ADAPTER = 0xcd2eb13D6831d4602D80E5db9230A57596CDCA63;

    function run() public returns (address) {

        // TODO: replace with the deployer's private key for actual deployment
        // uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(1);
        vm.startBroadcast(scriptDeployer);

        MigrationOFT migrationOFT = new MigrationOFT("Migration Token", "MT", DEPLOYMENT_LZ_ENDPOINT, scriptDeployer, DEPLOYMENT_OFT_ADAPTER);
        migrationOFTAddress = address(migrationOFT);
        console.log("MigrationOFT: ", migrationOFTAddress);

        migrationOFT.setPeer(L1_EID, LayerZeroHelpers._toBytes32(L1_OFT_ADAPTER));
        _setDVN(L1_EID);
        _appendEnforcedOptions(L1_EID);

        migrationOFT.setEnforcedOptions(enforcedOptions);
        migrationOFT.setDelegate(DEPLOYMENT_CONTRACT_CONTROLLER);
        migrationOFT.transferOwnership(DEPLOYMENT_CONTRACT_CONTROLLER);

        vm.stopBroadcast();

        return migrationOFTAddress;
    }

    // sets the specific DVN confgiuration we need for the migration OFT
    // - standard config for the send library to allow the migration OFT to send migration messages
    // - a dead DVN config for the receive library to block any incoming messages
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

        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(migrationOFTAddress, DEPLOYMENT_SEND_LID_302, params);

        address[] memory deadDVN = new address[](1);
        deadDVN[0] = DEAD_DVN;
        ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: deadDVN,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(migrationOFTAddress, DEPLOYMENT_RECEIVE_LIB_302, params);
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
