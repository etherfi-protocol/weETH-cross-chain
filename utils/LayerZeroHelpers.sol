// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import "../contracts/PairwiseRateLimiter.sol";

import "./L2Constants.sol";

library LayerZeroHelpers {
    using OptionsBuilder for bytes;
    // TODO: move all layerzero helper functions here

    // Converts an address to bytes32
    function _toBytes32(address addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Creates a RateLimiter.RateLimitConfig struct based on the inputs provided
    function _getRateLimitConfig(uint32 peerEid, uint256 limit, uint256 window) internal pure returns (PairwiseRateLimiter.RateLimitConfig memory) {
       return PairwiseRateLimiter.RateLimitConfig({ 
        peerEid: peerEid,
        limit: limit,
        window: window
       });
    }

    // Encodes a UlnConfig struct for the provided DVNs as bytes. This is how the DVN data is stored in the layerzero endpoint
    function _getExpectedUln(address lzDvn, address nethermindDvn) public pure returns (bytes memory) {
        address[] memory requiredDVNs = new address[](2);

        // The DVN arrays are sorted in ascending order (enforced by requires statements in the layerzero endpoint contract)
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

        return abi.encode(ulnConfig);
    }

    // get a dead ULN (unreachable path)
    function _getDeadUln() public pure returns (bytes memory) {
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

        return abi.encode(ulnConfig);
    }

    function getDVNConfig(uint32 eid, address[2] memory lzDvn) internal pure returns (SetConfigParam[] memory) {
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

        params[0] = SetConfigParam(eid, 2, abi.encode(ulnConfig));

        return params;
    }

    function getDVNConfigWithBlockConfirmations(uint32 eid, address[2] memory lzDvn, uint64 numConfirmations) internal pure returns (SetConfigParam[] memory) {
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
            confirmations: numConfirmations,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(eid, 2, abi.encode(ulnConfig));

        return params;
    }

}
