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
import "../../contracts/PairwiseRateLimiter.sol";

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";


// forge script scripts/OFTDeployment/02_UpdateOFTPeersTransactions.s.sol:UpdateOFTPeersTransactions
contract UpdateOFTPeersTransactions is Script, Constants, LayerZeroHelpers {
    using OptionsBuilder for bytes;

    string setPeerDataString;
    string setInboundRateLimitDataString;
    string setOutboundRateLimitDataString;
    string setEnforcedOptionsString;

    PairwiseRateLimiter.RateLimitConfig[] public deploymentRateLimitConfigs;

    function _initialize() internal {
        // Some of the transactions are the same cross chain so they are configured here:
        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", DEPLOYMENT_EID, _toBytes32(DEPLOYMENT_OFT));
        setPeerDataString = iToHex(setPeerData);

        PairwiseRateLimiter.RateLimitConfig[] memory rateLimitConfigs = new PairwiseRateLimiter.RateLimitConfig[](1);
        rateLimitConfigs[0] = _getRateLimitConfig(DEPLOYMENT_EID, LIMIT, WINDOW);
        bytes memory setInboundRateLimitData = abi.encodeWithSignature("setInboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs);
        bytes memory setOutboundRateLimitData = abi.encodeWithSignature("setOutboundRateLimits((uint32,uint256,uint256)[])", rateLimitConfigs);
        setInboundRateLimitDataString = iToHex(setInboundRateLimitData);
        setOutboundRateLimitDataString = iToHex(setOutboundRateLimitData);

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
        bytes memory setEnforcedOptionsData = abi.encodeWithSignature("setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions);
        setEnforcedOptionsString = iToHex(setEnforcedOptionsData);
    }

    function _build_configuration_transaction_L1() internal view returns (string memory) {
        // Get hex strings from the address vars
        string memory l1OftAdapterString = iToHex(abi.encodePacked(L1_OFT_ADAPTER));
        string memory l1EndpointString = iToHex(abi.encodePacked(L1_ENDPOINT));
        string memory MainnetJson = _getGnosisHeader("1");

        // Adding the transactions to update the OFT adapter
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setPeerDataString, false));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setEnforcedOptionsString, false));

        // Configure the rate limiting on the L1
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setInboundRateLimitDataString, false));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1OftAdapterString, setOutboundRateLimitDataString, false));

        // Transactions to update the mainnet LZ endpoint
        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_OFT_ADAPTER, L1_SEND_302, _getDVNConfig(L1_DVN)));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1EndpointString, setLZConfigSend, false));
        string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_OFT_ADAPTER, L1_RECEIVE_302, _getDVNConfig(L1_DVN)));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(l1EndpointString, setLZConfigReceive, true));

        return MainnetJson;
    }

    function _build_configuration_transaction_L2(ConfigPerL2 memory _l2) internal view returns (string memory) {
        // Get hex strings from the address vars
        string memory l2OftString = iToHex(abi.encodePacked(_l2.L2_OFT));
        string memory l2EndpointString = iToHex(abi.encodePacked(_l2.L2_ENDPOINT));

        string memory L2Json = _getGnosisHeader(_l2.CHAIN_ID);

        // Transactions to update the OFT contract
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2OftString, setPeerDataString, false));
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2OftString, setInboundRateLimitDataString, false));
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2OftString, setOutboundRateLimitDataString, false));
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2OftString, setEnforcedOptionsString, false));

        // Transactions to update the corresponding chains LZ endpoint
        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.SEND_302, _getDVNConfig(_l2.LZ_DVN)));
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2EndpointString, setLZConfigSend, false));
        string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", _l2.L2_OFT, _l2.RECEIVE_302, _getDVNConfig(_l2.LZ_DVN)));
        L2Json = string.concat(L2Json, _getGnosisTransaction(l2EndpointString, setLZConfigReceive, true));

        return L2Json;
    }

    function run() public {
        console.log("Initialize");
        _initialize();

        console.log("Building transaction batch for mainnet");
        string memory MainnetJson = _build_configuration_transaction_L1();
        vm.writeJson(MainnetJson, "./output/mainnet.json");

        for (uint256 i = 0; i < L2s.length; i++) {
            console.log("Building transaction batch for %s", L2s[i].NAME);
            string memory L2Json = _build_configuration_transaction_L2(L2s[i]);
            vm.writeJson(L2Json, string.concat("./output/", L2s[i].NAME, ".json"));
        }

        // TODO: remove after swell deployment
        // additional transaction to set swell config to include nethermind for all peers
        string memory deploymentEndpointString = iToHex(abi.encodePacked(DEPLOYMENT_LZ_ENDPOINT));

        string memory deploymentJson = _getGnosisHeader(DEPLOYMENT_CHAIN_ID);
        address[2] memory deploymentDVNs = [DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN];

        // set the config for all the L2s
        for (uint256 i = 0; i < L2s.length; i++) {
            string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", DEPLOYMENT_OFT, DEPLOYMENT_SEND_LID_302, _getDVNConfig(deploymentDVNs, L2s[i].L2_EID)));
            deploymentJson = string.concat(deploymentJson, _getGnosisTransaction(deploymentEndpointString, setLZConfigSend, false));
            string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, _getDVNConfig(deploymentDVNs, L2s[i].L2_EID)));
            deploymentJson = string.concat(deploymentJson, _getGnosisTransaction(deploymentEndpointString, setLZConfigReceive, false));
        }

        string memory setLZConfigSend = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", DEPLOYMENT_OFT, DEPLOYMENT_SEND_LID_302,  _getDVNConfig(deploymentDVNs, L1_EID)));
        deploymentJson = string.concat(deploymentJson, _getGnosisTransaction(deploymentEndpointString, setLZConfigSend, false));
        string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, _getDVNConfig(deploymentDVNs, L1_EID)));
        deploymentJson = string.concat(deploymentJson, _getGnosisTransaction(deploymentEndpointString, setLZConfigReceive, true));

        vm.writeJson(deploymentJson, "./output/swellSetConfig.json");
    }

    // Gets the DVN config for a set of lzDvns. `EID` is the EID of the OFT that is currently being deployed
    function _getDVNConfig(address[2] memory lzDvn) internal pure returns (SetConfigParam[] memory) {
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

        params[0] = SetConfigParam(DEPLOYMENT_EID, 2, abi.encode(ulnConfig));

        return params;
    }

    // TODO: remove after swell deployment
    function _getDVNConfig(address[2] memory lzDvn, uint32 peerId) internal pure returns (SetConfigParam[] memory) {
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

        params[0] = SetConfigParam(peerId, 2, abi.encode(ulnConfig));

        return params;
    }

    // Get the gnosis transaction header
    function _getGnosisHeader(string memory chainId) internal pure returns (string memory) {
        return string.concat('{"chainId":"', chainId, '","meta": { "txBuilderVersion": "1.16.5" }, "transactions": [');
    }

    // Create a gnosis transaction
    // ether sent value is always 0 for our usecase
    function _getGnosisTransaction(string memory to, string memory data, bool isLast) internal pure returns (string memory) {
        string memory suffix = isLast ? ']}' : ',';
        return string.concat('{"to":"', to, '","value":"0","data":"', data, '"}', suffix);
    }

    // Helper function to convert bytes to hex strings 
    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal conversion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
