// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract GenerationMigrationTransactions is Script, Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;

    RateLimiter.RateLimitConfig[] public deploymentRateLimitConfigs;

    function run() public {
        console.log("Building mainnet migration transaction:");
        string memory MainnetJson = _mainnetMigrationPeer();
        vm.writeJson(MainnetJson, "./output/mainnet-migration-peer.json");

        for (uint256 i = 0; i < L2s.length; i++) {
            console.log("Building transactions for:", L2s[i].NAME);

            string memory disconnectJson = _disconnectPeerTransaction(L2s[i]);
            vm.writeJson(disconnectJson, string.concat("./output/disconnect-", L2s[i].NAME, ".json"));

            string memory reconnectJson = _reconnectPeerTransaction(L2s[i]);
            vm.writeJson(reconnectJson, string.concat("./output/reconnect-", L2s[i].NAME, ".json"));
        }
    }

    function _disconnectPeerTransaction(ConfigPerL2 memory _l2) internal pure returns (string memory) { 
        string memory transactionJson = _getGnosisHeader(_l2.CHAIN_ID);
        string memory l2EndpointString = iToHex(abi.encodePacked(_l2.L2_OFT));

        // Setting send pathway for all peers to dead DVN to disable sends from this chain 
        for (uint256 i = 0; i < L2s.length; i++) {
            if (L2s[i].NAME == _l2.NAME) {
                continue;
            }
            string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.SEND_302, _getDeadDVNConfig(L2s[i].L2_EID)));
            transactionJson = string.concat(transactionJson, _getGnosisTransaction(l2EndpointString, setLZConfigSend, false));
        }
        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.SEND_302, _getDeadDVNConfig(L1_EID)));
        transactionJson = string.concat(transactionJson, _getGnosisTransaction(l2EndpointString, setLZConfigSend, true));

        return transactionJson;
    }

    function _reconnectPeerTransaction(ConfigPerL2 memory _l2) internal pure returns (string memory) {
        string memory transactionJson = _getGnosisHeader(_l2.CHAIN_ID);
        string memory l2OftString = iToHex(abi.encodePacked(_l2.L2_OFT));
        string memory l2EndpointString = iToHex(abi.encodePacked(_l2.L2_OFT));

        // Setting mainnet peer to new OFT adapter 
        string memory setPeer = iToHex(abi.encodeWithSignature("setPeer(uint32,bytes32)", L1_EID, _toBytes32(DEPLOYMENT_OFT_ADAPTER)));
        transactionJson = string.concat(transactionJson, _getGnosisTransaction(l2OftString, setPeer, false));
        // Reseting send pathway for all peers
        for (uint256 i = 0; i < L2s.length; i++) {
            if (L2s[i].NAME == _l2.NAME) {
                continue;
            }
            string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.SEND_302, _getDVNConfig(_l2.LZ_DVN, L2s[i].L2_EID)));
            transactionJson = string.concat(setLZConfigSend, _getGnosisTransaction(l2EndpointString, setLZConfigSend, false));
        }
        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.SEND_302, _getDVNConfig(_l2.LZ_DVN, L1_EID)));
        transactionJson = string.concat(transactionJson, _getGnosisTransaction(l2EndpointString, setLZConfigSend, true));

        return transactionJson;
    }

    // adds the migration OFT as a peer to the mainnet OFT adapter
    function _mainnetMigrationPeer() internal view returns (string memory) {
        string memory l1OftAdapterString = iToHex(abi.encodePacked(L1_OFT_ADAPTER));
        string memory l1EndpointString = iToHex(abi.encodePacked(L1_ENDPOINT));
        string memory MainnetJson = _getGnosisHeader("1");

        // Adding the transactions to update the OFT adapter
        string memory setPeerDataString = iToHex(abi.encodeWithSignature("setPeer(uint32,bytes32)", DEPLOYMENT_EID, _toBytes32(DEPLOYMENT_OFT)));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setPeerDataString, false));
        EnforcedOptionParam[] memory enforcedOptions;
        enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: DEPLOYMENT_EID,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: DEPLOYMENT_EID,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });

        string memory setEnforcedOptionsString = iToHex( abi.encodeWithSignature("setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setEnforcedOptionsString, false));

        // Transactions to update the corresponding chains LZ endpoint
        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_OFT_ADAPTER, L1_SEND_302, _getDVNConfig(L1_DVN, DEPLOYMENT_EID)));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1EndpointString, setLZConfigSend, true));

        return MainnetJson;
    }

    // setting this sending peer to dead DVN
    function _getDeadDVNConfig(uint32 dist_EID) internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = 0x000000000000000000000000000000000000dEaD;

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        // peer is always mainnet for migration
        params[0] = SetConfigParam(L1_EID, 2, abi.encode(ulnConfig));
        return params;
    }

    function _getDVNConfig(address[2] memory lzDvn, uint32 peerEID) internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);
        if (lzDvn[0] > lzDvn[1]) {
            requiredDVNs[0] = lzDvn[1];
            requiredDVNs[1] = lzDvn[0];
        } else {
            requiredDVNs[0] = lzDvn[0];
            requiredDVNs[1] = lzDvn[1];
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        // peer chain is always mainnet for migration
        params[0] = SetConfigParam(peerEID, 2, abi.encode(ulnConfig));

        return params;
    }


    function _getGnosisHeader(string memory chainId) internal pure returns (string memory) {
        return string.concat('{"chainId":"', chainId, '","meta": { "txBuilderVersion": "1.16.5" }, "transactions": [');
    }

    function _getGnosisTransaction(string memory to, string memory data, bool isLast) internal pure returns (string memory) {
        string memory suffix = isLast ? ']}' : ',';
        return string.concat('{"to":"', to, '","value":"0","data":"', data, '"}', suffix);
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
