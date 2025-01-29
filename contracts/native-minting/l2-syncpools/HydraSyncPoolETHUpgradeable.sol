// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {BaseMessengerUpgradeable} from "../layerzero-base/BaseMessengerUpgradeable.sol";
import {BaseReceiverUpgradeable} from "../layerzero-base/BaseReceiverUpgradeable.sol";
import {L2BaseSyncPoolUpgradeable} from "../layerzero-base/L2BaseSyncPoolUpgradeable.sol";
import {IStargate} from "../../../interfaces/IStargate.sol";
import { MessagingFee, OFTReceipt, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {Constants} from "../../libraries/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Hydra Cross-Chain Sync Pool for ETH
 * @dev A sync pool that supports ETH transfers across hydra enabled blockchain networks
 * This contract enables ETH to be sent back to mainnet during the sync process
 */
contract HydraSyncPoolETHUpgradeable is L2BaseSyncPoolUpgradeable, BaseMessengerUpgradeable, BaseReceiverUpgradeable {
    using OptionsBuilder for bytes;

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
     * @param messenger Address of the messenger contract typically `StargateOFTETH` for Hydra chains
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
        emit DepositWithReferral(msg.sender, amountIn, referral);
        return super.deposit(tokenIn, amountIn, minAmountOut);
    }

    /**
     * @dev Quote the messaging fee for the 2 messages to be sent
     * @param tokenIn Address of the token
     * @param extraOptions Extra options for the messaging protocol
     * @param payInLzToken Whether to pay the fee in LZ token
     * @return standardFee Messaging fee for the standard sync message
     * @return totalFee total native fee for both Hydra and sync messaging
     */
    function quoteSyncTotal(address tokenIn, bytes calldata extraOptions, bool payInLzToken)
        public
        view
        virtual
        returns (MessagingFee memory standardFee, uint256 totalFee)
    {
        standardFee = super.quoteSync(tokenIn, extraOptions, payInLzToken);
        
        Token memory token = getTokenData(tokenIn);

        (, MessagingFee memory hydraFee) = _buildSendParam(token.unsyncedAmountIn, token.unsyncedAmountOut);

        totalFee = standardFee.nativeFee + hydraFee.nativeFee;
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
     * @dev Override the _payNative function to allow multiple LayerZero messages in a single transaction
     */
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    /**
     * @dev Internal function to sync tokens across chains
     * sync message is sent with the stargate token transfer as a composed message
     * @param dstEid Destination endpoint ID
     * @param l2TokenIn Address of the deposit token on Layer 2
     * @param l1TokenIn Address of the deposit token on Layer 1
     * @param amountIn Amount of tokens deposited on Layer 2
     * @param amountOut Amount of weETH minted on Layer 2
     * @param extraOptions Extra options for the messaging protocol
     * @param fee Messaging fee
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
        // wETH deposited on alt chain will be unwrapped for ETH on mainnet
        if (l1TokenIn != Constants.ETH_ADDRESS || l2TokenIn != HYDRA_WETH) {
            revert HydraSyncPoolETH__OnlyETH();
        }
        
        IStargate stargate = IStargate(getMessenger());

        (SendParam memory sendParam, MessagingFee memory hydraFee) = _buildSendParam(amountIn, amountOut);

        IERC20(HYDRA_WETH).approve(address(stargate), amountIn);
        
        (MessagingReceipt memory _msgReceipt, OFTReceipt memory oftReceipt,) = stargate.sendToken{ value: hydraFee.nativeFee }(sendParam, hydraFee, msg.sender);

        // amount of ETH received on mainnet will be less then the amount of wETH sent due to stargate fee
        amountIn = oftReceipt.amountReceivedLD;
        MessagingReceipt memory receipt = super._sync(dstEid, l2TokenIn, l1TokenIn, amountIn, amountOut, extraOptions, fee);

        return receipt;
    }

    /**
     * @dev Builds the parameters needed for sending tokens through Stargate and quotes the messaging fee
     * @param amountIn Amount of tokens to be sent from source chain
     * @param amountOut Amount of weETH minted on source chain 
     * @return SendParam Constructed parameters for Stargate's sendToken function
     * @return MessagingFee The quoted messaging fee
     */
    function _buildSendParam(
        uint256 amountIn,
        uint256 amountOut
    ) internal view returns (SendParam memory, MessagingFee memory) {

        address receiver = getReceiver();
        uint32 dstEid = getDstEid();
        IStargate stargate = IStargate(getMessenger());

        bytes memory message = abi.encode(amountOut);

        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: _addressToBytes32(receiver),
            amountLD: amountIn,
            minAmountLD: amountIn,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 300_000, 0),
            composeMsg: message,
            oftCmd: ""
        });

        (, ,OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory messagingFee = stargate.quoteSend(sendParam, false);

        return (sendParam, messagingFee);
    }

    /**
     * @dev Convert an address to bytes32
     * @param _addr Address to convert
     * @return bytes32 representation of the address
     */
    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
