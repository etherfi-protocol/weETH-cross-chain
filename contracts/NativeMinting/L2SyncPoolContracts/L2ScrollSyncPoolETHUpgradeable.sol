
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {BaseMessengerUpgradeable} from "../LayerZeroBaseContracts/BaseMessengerUpgradeable.sol";
import {BaseReceiverUpgradeable} from "../LayerZeroBaseContracts/BaseReceiverUpgradeable.sol";
import {L2BaseSyncPoolUpgradeable} from "../LayerZeroBaseContracts/L2BaseSyncPoolUpgradeable.sol";
import {IL2ScrollMessenger} from "../../../interfaces/IL2ScrollMessenger.sol";
import {Constants} from "../../libraries/Constants.sol";
import {IL1Receiver} from "../../../interfaces/IL1Receiver.sol";

/**
 * @title L2 Scroll Stack Sync Pool for ETH
 * @dev A sync pool that only supports ETH on Scroll Stack L2s
 * This contract allows to send ETH from L2 to L1 during the sync process
 */
contract L2ScrollSyncPoolETHUpgradeable is L2BaseSyncPoolUpgradeable, BaseMessengerUpgradeable, BaseReceiverUpgradeable {

    event DepositWithReferral(address indexed sender, uint256 amount, address referral);

    error L2ScrollStackSyncPoolETH__OnlyETH();

    /**
     * @dev Constructor for L2 Scroll Stack Sync Pool for ETH
     * @param endpoint Address of the LayerZero endpoint
     */
    constructor(address endpoint) L2BaseSyncPoolUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param l2ExchangeRateProvider Address of the exchange rate provider
     * @param rateLimiter Address of the rate limiter
     * @param tokenOut Address of the token to mint on Layer 2
     * @param dstEid Destination endpoint ID (most of the time, the Layer 1 endpoint ID)
     * @param messenger Address of the messenger contract (most of the time, the L2 native bridge address)
     * @param receiver Address of the receiver contract (most of the time, the L1 receiver contract)
     * @param delegate Address of the owner
     */
    function initialize(
        address l2ExchangeRateProvider,
        address rateLimiter,
        address tokenOut,
        uint32 dstEid,
        address messenger,
        address receiver,
        address delegate
    ) external virtual initializer {
        
        __L2BaseSyncPool_init(l2ExchangeRateProvider, rateLimiter, tokenOut, dstEid, delegate);
        __BaseMessenger_init(messenger);
        __BaseReceiver_init(receiver);
        __Ownable_init(delegate);
    }

    /**
     * @dev Only allows ETH to be received
     * @param tokenIn The token address
     * @param amountIn The amount of tokens
     */
    function _receiveTokenIn(address tokenIn, uint256 amountIn) internal virtual override {
        if (tokenIn != Constants.ETH_ADDRESS) revert L2ScrollStackSyncPoolETH__OnlyETH();

        super._receiveTokenIn(tokenIn, amountIn);
    }

    /**
     * @dev Internal function to sync tokens to L1
     * This will send an additional message to the messenger contract after the LZ message
     * This message will contain the ETH that the LZ message anticipates to receive
     * @param dstEid Destination endpoint ID
     * @param l1TokenIn Address of the token on Layer 1
     * @param amountIn Amount of tokens deposited on Layer 2
     * @param amountOut Amount of tokens minted on Layer 2
     * @param extraOptions Extra options for the messaging protocol
     * @param fee Messaging fee
     * @return receipt Messaging receipt
     */
    function _sync(
        uint32 dstEid,
        address l2TokenIn,
        address l1TokenIn,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata extraOptions,
        MessagingFee calldata fee
    ) internal virtual override returns (MessagingReceipt memory) {
        if (l1TokenIn != Constants.ETH_ADDRESS || l2TokenIn != Constants.ETH_ADDRESS) {
            revert L2ScrollStackSyncPoolETH__OnlyETH();
        }

        address receiver = getReceiver();
        address messenger = getMessenger();

        uint32 originEid = endpoint.eid();

        MessagingReceipt memory receipt =
            super._sync(dstEid, l2TokenIn, l1TokenIn, amountIn, amountOut, extraOptions, fee);

        bytes memory data = abi.encode(originEid, receipt.guid, l1TokenIn, amountIn, amountOut);
        bytes memory message = abi.encodeCall(IL1Receiver.onMessageReceived, data);

        IL2ScrollMessenger(messenger).sendMessage{value: amountIn}(receiver, amountIn, message, 0);

        return receipt;
    }

    /** 
     * @dev Deposit function with referral event 
     */
    function deposit(
        address tokenIn,
        uint256 amountIn, 
        uint256 minAmountOut, 
        address referral
    ) public payable returns (uint256 amountOut) {
        emit DepositWithReferral(msg.sender, msg.value, referral);
        return super.deposit(tokenIn, amountIn, minAmountOut);
    }
}
