// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {BaseMessengerUpgradeable} from "../LayerZeroBaseContracts/BaseMessengerUpgradeable.sol";
import {BaseReceiverUpgradeable} from "../LayerZeroBaseContracts/BaseReceiverUpgradeable.sol";
import {L2BaseSyncPoolUpgradeable} from "../LayerZeroBaseContracts/L2BaseSyncPoolUpgradeable.sol";
import {IStargate} from "../../../interfaces/IStargate.sol";
import { MessagingFee, OFTReceipt, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {Constants} from "../../libraries/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console.sol";

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

    /**
     * @dev Quote the messaging fee for the 2 messages to be sent
     * @param tokenIn Address of the token
     * @param extraOptions Extra options for the messaging protocol
     * @param payInLzToken Whether to pay the fee in LZ token
     * @return standardFee Messaging fee for the standard message
     * @return totalFee total native fee for both Hydra and LZ messaging
     */
    function quoteSyncTotal(address tokenIn, bytes calldata extraOptions, bool payInLzToken)
        public
        view
        virtual
        returns (MessagingFee memory standardFee, uint256 totalFee)
    {
        standardFee = super.quoteSync(tokenIn, extraOptions, payInLzToken);
        
        Token memory token = getTokenData(tokenIn);

        (, MessagingFee memory hydraFee) = _buildSendParam(tokenIn, token.unsyncedAmountIn, token.unsyncedAmountOut, bytes32(0));

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
     * @dev Internal function to pay the native fee associated with the message.
     * @param _nativeFee The native fee to be paid.
     * @return nativeFee The amount of native currency paid.
     *
     * @dev Override of base _payNative that allows msg.value to be greater than the required fee
     * @dev necessary when to send multiple LayerZero messages in a single transaction
     * @dev where msg.value contains multiple lzFees
     */
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
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

        IStargate stargate = IStargate(getMessenger());

        MessagingReceipt memory receipt =
            super._sync(targetChainId, sourceTokenAddress, targetTokenAddress, amountIn, amountOut, extraOptions, fee);

        (SendParam memory sendParam, MessagingFee memory messagingFee) = _buildSendParam(sourceTokenAddress, amountIn, amountOut, receipt.guid);

        IERC20(HYDRA_WETH).approve(address(stargate), amountIn);
        stargate.sendToken{ value: messagingFee.nativeFee }(sendParam, messagingFee, address(0x0));

        return receipt;
    }

    /**
     * @dev Builds the parameters needed for sending tokens through Stargate and quotes the messaging fee
     * @param tokenIn Address of the input token (WETH) on the source chain
     * @param amountIn Amount of tokens to be sent from source chain
     * @param amountOut Amount of tokens to be received on target chain
     * @param guid Unique identifier of the previous LayerZero message (used for message correlation)
     * @return SendParam Constructed parameters for Stargate's sendToken function
     * @return MessagingFee The quoted messaging fee
     */
    function _buildSendParam(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 guid
    ) internal view returns (SendParam memory, MessagingFee memory) {

        address receiver = getReceiver();
        uint32 dstEid = getDstEid();
        uint32 originEid = endpoint.eid();
        IStargate stargate = IStargate(getMessenger());
        
        bytes memory composeMsg = abi.encode(originEid, guid, tokenIn, amountIn, amountOut);

        console.logBytes(composeMsg);

        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: _addressToBytes32(receiver),
            amountLD: amountIn,
            minAmountLD: amountIn,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 1_000_000, 0),
            composeMsg: composeMsg,
            oftCmd: ""
        });

        (, ,OFTReceipt memory receipt) = stargate.quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        console.log(receipt.amountReceivedLD);

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
