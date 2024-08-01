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
import "../../contracts/MigrationOFT.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";


contract DeployMigrationOFT is Script, Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;

    address public migrationOFTAddress;
    EnforcedOptionParam[] public enforcedOptions;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        MigrationOFT migrationOFT = new MigrationOFT("Migration Token", "MT", DEPLOYMENT_LZ_ENDPOINT, scriptDeployer, DEPLOYMENT_OFT_ADAPTER);
        migrationOFTAddress = address(migrationOFT);
        console.log("MigrationOFT: ", migrationOFTAddress);

        migrationOFT.setPeer(L1_EID, _toBytes32(L1_OFT_ADAPTER));
        _setDVN(L1_EID);
        _appendEnforcedOptions(L1_EID);

        migrationOFT.setEnforcedOptions(enforcedOptions);

        migrationOFT.transferOwnership(DEPLOYMENT_CONTRACT_CONTROLLER);
        vm.stopBroadcast();
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

        ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT).setConfig(migrationOFTAddress, DEPLOYMENT_SEND_LID_302, params);
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