// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {BaseMessengerUpgradeable} from "../LayerZeroBaseContracts/BaseMessengerUpgradeable.sol";
import {BaseReceiverUpgradeable} from "../LayerZeroBaseContracts/BaseReceiverUpgradeable.sol";
import {L2BaseSyncPoolUpgradeable} from "../LayerZeroBaseContracts/L2BaseSyncPoolUpgradeable.sol";
// import {IHydraMessenger} from "../../../interfaces/IHydraMessenger.sol";
import {Constants} from "../../libraries/Constants.sol";
// import {IChainReceiver} from "../../../interfaces/IChainReceiver.sol";

/**
 * @title Hydra Cross-Chain Sync Pool for ETH
 * @dev A sync pool that supports ETH transfers across hydra enabled blockchain networks
 * This contract enables ETH to be sent back to mainnet during the sync process
 */
contract HydraSyncPoolETHUpgradeable is L2BaseSyncPoolUpgradeable, BaseMessengerUpgradeable, BaseReceiverUpgradeable {

    address immutable HYDRA_WETH;

    event DepositWithReferral(address indexed sender, uint256 amount, address referral);

    error HydraSyncPoolETH__OnlyETH();

    /**
     * @dev Constructor for Hydra Cross-Chain Sync Pool for ETH
     * @param endpoint Address of the LayerZero endpoint
     * @param weth Address of the hydra wETH contract on the target chain
     */
    constructor(address endpoint, address weth) L2BaseSyncPoolUpgradeable(endpoint) {
        HYDRA_WETH = weth;

        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param exchangeRateProvider Address of the exchange rate provider
     * @param rateLimiter Address of the rate limiter
     * @param tokenOut Address of the token to mint on the target chain
     * @param targetChainId Target chain endpoint ID
     * @param messenger Address of the messenger contract typically `StargateOFTETH` for hydra chains
     * @param receiver Address of the receiver contract on the target chain
     * @param delegate Address of the owner
     */
    function initialize(
        address exchangeRateProvider,
        address rateLimiter,
        address tokenOut,
        uint32 targetChainId,
        address messenger,
        address receiver,
        address delegate
    ) external virtual initializer {

        __L2BaseSyncPool_init(exchangeRateProvider, rateLimiter, tokenOut, targetChainId, delegate);
        __BaseMessenger_init(messenger);
        __BaseReceiver_init(receiver);
        __Ownable_init(delegate);
    }

    /**
     * @dev Only allows hydra wETH to be received
     * @param tokenIn The token address
     * @param amountIn The amount of tokens
     */
    function _receiveTokenIn(address tokenIn, uint256 amountIn) internal virtual override {
        if (tokenIn != HYDRA_WETH) revert HydraSyncPoolETH__OnlyETH();

        super._receiveTokenIn(tokenIn, amountIn);
    }

    /**
     * @dev Internal function to sync tokens across chains
     * This will send a message through the Hydra messenger after the LZ message
     * The message will contain the ETH amount to be bridged to the target chain
     * @param targetChainId Target chain endpoint ID
     * @param sourceTokenAddress Address of the token on source chain
     * @param targetTokenAddress Address of the token on target chain
     * @param amountIn Amount of tokens deposited on source chain
     * @param amountOut Amount of tokens to be minted on target chain
     * @param extraOptions Extra options for the messaging protocol
     * @param fee Messaging fee
     * @return receipt Messaging receipt
     */
    function _sync(
        uint32 targetChainId,
        address sourceTokenAddress,
        address targetTokenAddress,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata extraOptions,
        MessagingFee calldata fee
    ) internal virtual override returns (MessagingReceipt memory) {
        // wETH deposited on alt chain will be unwrapped for ETH on mainnet
        if (targetTokenAddress != Constants.ETH_ADDRESS || sourceTokenAddress != HYDRA_WETH) {
            revert HydraSyncPoolETH__OnlyETH();
        }

        address receiver = getReceiver();
        address messenger = getMessenger();

        uint32 sourceChainId = endpoint.eid();

        MessagingReceipt memory receipt =
            super._sync(targetChainId, sourceTokenAddress, targetTokenAddress, amountIn, amountOut, extraOptions, fee);

        bytes memory data = abi.encode(sourceChainId, receipt.guid, targetTokenAddress, amountIn, amountOut);

        return receipt;
    }

    /** 
     * @dev Deposit function with referral tracking
     * @param tokenIn Address of the input token (must be ETH address)
     * @param amountIn Amount of ETH to deposit
     * @param minAmountOut Minimum amount to receive on the target chain
     * @param referral Address of the referrer
     * @return amountOut The amount that will be received on the target chain
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
