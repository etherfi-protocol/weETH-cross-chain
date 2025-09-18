import "forge-std/Script.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract generateEnforcedOptionsTransactions is Script, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;

    function run() public {
        EnforcedOptionParam[] memory enforcedOptions = getEnforcedOptions(L1_EID);
        string memory setEnforcedOptionsData = iToHex(abi.encodeWithSignature("setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions));

        string memory beraJson = _getGnosisHeader(BERA.CHAIN_ID);
        beraJson = string.concat(beraJson, _getGnosisTransaction(iToHex(abi.encodePacked(BERA.L2_OFT)), setEnforcedOptionsData, true));

        vm.writeJson(beraJson, "./output/berachainEnforcedOptions.json");
    }

    function getEnforcedOptions(uint32 _eid) public pure returns (EnforcedOptionParam[] memory) {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: _eid,
            msgType: 0,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });
        
        enforcedOptions[1] = EnforcedOptionParam({
            eid: _eid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });
        enforcedOptions[2] = EnforcedOptionParam({
            eid: _eid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(400_000, 0)
        });

        return enforcedOptions; 
    }

}
