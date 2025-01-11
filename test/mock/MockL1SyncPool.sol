// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {
    OAppReceiverUpgradeable,
    OAppCoreUpgradeable
} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppReceiverUpgradeable.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract MockL1SyncPool is OAppReceiverUpgradeable, ReentrancyGuardUpgradeable {
    event MessageReceived(
        uint32 indexed originEid,
        bytes32 indexed guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );
    
    event LZMessageReceived(
        uint32 indexed srcEid,
        bytes32 indexed guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    error UnauthorizedCaller();
    error EtherfiL1SyncPoolETH__OnlyETH();
    error EtherfiL1SyncPoolETH__InvalidAmountIn();

    mapping(uint32 => address) public receivers;

    constructor(address endpoint) OAppCoreUpgradeable(endpoint) {}

    function initialize(address delegate) public initializer {
        __ReentrancyGuard_init();
        __OAppCore_init(delegate);
        __Ownable_init(delegate);
    }

    function setReceiver(uint32 originEid, address receiver) public {
        receivers[originEid] = receiver;
    }

    function onMessageReceived(
        uint32 originEid,
        bytes32 guid,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) public payable nonReentrant {
        if (msg.sender != receivers[originEid]) revert UnauthorizedCaller();

        if (tokenIn != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) revert EtherfiL1SyncPoolETH__OnlyETH();
        if (amountIn != msg.value) revert EtherfiL1SyncPoolETH__InvalidAmountIn();

        emit MessageReceived(originEid, guid, tokenIn, amountIn, amountOut);
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address,
        bytes calldata
    ) internal override {
        (address tokenIn, uint256 amountIn, uint256 amountOut) = abi.decode(
            message,
            (address, uint256, uint256)
        );

        if (tokenIn != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) revert EtherfiL1SyncPoolETH__OnlyETH();

        emit LZMessageReceived(origin.srcEid, guid, tokenIn, amountIn, amountOut);
    }
}
