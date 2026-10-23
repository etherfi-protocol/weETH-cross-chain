// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title OFTEndpointMock
 * @dev Endpoint mock that accepts OFT sends and records the last message, so unit tests can run
 * the full `send` path without LayerZero libraries.
 */
contract OFTEndpointMock {
    uint32 public immutable eid;
    uint256 public constant NATIVE_FEE = 0.001 ether;

    uint64 public nonce;
    uint32 public lastDstEid;
    bytes public lastMessage;

    constructor(uint32 _eid) {
        eid = _eid;
    }

    function setDelegate(address) external {}

    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        return MessagingFee(NATIVE_FEE, 0);
    }

    function send(MessagingParams calldata _params, address) external payable returns (MessagingReceipt memory) {
        nonce++;
        lastDstEid = _params.dstEid;
        lastMessage = _params.message;
        return MessagingReceipt(keccak256(abi.encode(nonce, _params.message)), nonce, MessagingFee(msg.value, 0));
    }
}
