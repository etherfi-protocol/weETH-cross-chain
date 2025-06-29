import "forge-std/Script.sol";
import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract generateCanaryTransactions is Script, L2Constants, GnosisHelpers {

    mapping(uint32 => address) public canaryDvns;

    function run() public {
        // ethereum canary dvn
        canaryDvns[1] = 0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd;
        // optimism canary dvn
        canaryDvns[10] = 0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f;
        // bsc canary dvn
        canaryDvns[56] = 0xfA9bA83C102283958B997Adc8B44ED3A3CdB5dDa;

        address[] memory existingDvns = new address[](2);
        existingDvns[0] = L1_DVN[0];
        existingDvns[1] = L1_DVN[1];
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = OP.L2_EID;
        targetEids[1] = BNB.L2_EID;

        _generate_canary_transaction(
            L1_ENDPOINT,
            "1",
            L1_OFT_ADAPTER,
            L1_SEND_302,
            L1_RECEIVE_302,
            existingDvns,
            canaryDvns[1],
            targetEids
        );

        existingDvns[0] = OP.LZ_DVN[0];
        existingDvns[1] = OP.LZ_DVN[1];
        targetEids[0] = L1_EID;
        targetEids[1] = BNB.L2_EID;

        _generate_canary_transaction(
            OP.L2_ENDPOINT,
            OP.CHAIN_ID,
            OP.L2_OFT,
            OP.SEND_302,
            OP.RECEIVE_302,
            existingDvns,
            canaryDvns[10],
            targetEids
        );

        existingDvns[0] = BNB.LZ_DVN[0];
        existingDvns[1] = BNB.LZ_DVN[1];
        targetEids[0] = L1_EID;
        targetEids[1] = OP.L2_EID;

        _generate_canary_transaction(
            BNB.L2_ENDPOINT,
            BNB.CHAIN_ID,
            BNB.L2_OFT,
            BNB.SEND_302,
            BNB.RECEIVE_302,
            existingDvns,
            canaryDvns[56],
            targetEids
        );
    }

    function _generate_canary_transaction(
        address endpoint,
        string memory chainId,
        address oft, 
        address sendLib, 
        address receiveLib,
        address[] memory currentDvns, 
        address canaryDvn,
        uint32[] memory targetEids
        ) internal returns (string memory) {
        
        string memory AddCanaryJson = _getGnosisHeader(chainId);

        for (uint32 i = 0; i < targetEids.length; i++) {
            string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", oft, sendLib, _getDVNConfig(targetEids[i], currentDvns, canaryDvn)));
            AddCanaryJson = string.concat(AddCanaryJson, _getGnosisTransaction(iToHex(abi.encodePacked(endpoint)), setLZConfigSend, false));

            string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", oft, receiveLib, _getDVNConfig(targetEids[i], currentDvns, canaryDvn)));
            bool lastTransaction = i == targetEids.length - 1;
            AddCanaryJson = string.concat(AddCanaryJson, _getGnosisTransaction(iToHex(abi.encodePacked(endpoint)), setLZConfigReceive, lastTransaction));
        }
        
        vm.writeJson(AddCanaryJson, string.concat("./output/", chainId, ".json"));
    }


    function _getDVNConfig(uint32 targetEid, address[] memory currentDvns, address canaryDvn) internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](3);

        requiredDVNs[0] = currentDvns[0];
        requiredDVNs[1] = currentDvns[1];
        requiredDVNs[2] = canaryDvn;
        
        // DVN array must be sorted in ascending order
        for (uint i = 0; i < requiredDVNs.length - 1; i++) {
            for (uint j = 0; j < requiredDVNs.length - i - 1; j++) {
                if (requiredDVNs[j] > requiredDVNs[j + 1]) {
                    address temp = requiredDVNs[j];
                    requiredDVNs[j] = requiredDVNs[j + 1];
                    requiredDVNs[j + 1] = temp;
                }
            }
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 3,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(targetEid, 2, abi.encode(ulnConfig));

        return params;
    }


}
