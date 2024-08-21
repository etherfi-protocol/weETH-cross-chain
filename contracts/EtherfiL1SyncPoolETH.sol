// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDummyToken} from "../interfaces/IDummyToken.sol";
import {L1BaseSyncPoolUpgradeable, Constants} from "./L1BaseSyncPoolUpgradeable.sol";
import {ILiquifier} from "../interfaces/ILiquifier.sol";
import {IWeEth} from "../interfaces/IWeEth.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ILiquidityPool} from "../interfaces/ILiquidityPool.sol";

contract EtherfiL1SyncPoolETH is L1BaseSyncPoolUpgradeable {
    error EtherfiL1SyncPoolETH__OnlyETH();
    error EtherfiL1SyncPoolETH__InvalidAmountIn();
    error EtherfiL1SyncPoolETH__UnsetDummyToken();

    ILiquifier private _liquifier;
    IERC20 private _eEth;

    mapping(uint32 => IDummyToken) private _dummyTokens;

    ILiquidityPool public liquidityPool;

    event LiquifierSet(address liquifier);
    event EEthSet(address eEth);
    event DummyTokenSet(uint32 originEid, address dummyToken);

    /**
     * @dev Constructor for Etherfi L1 Sync Pool ETH
     * @param endpoint Address of the LayerZero endpoint
     */
    constructor(address endpoint) L1BaseSyncPoolUpgradeable(endpoint) {}

    /**
     * @dev Initialize the contract
     * @param liquifier Address of the liquifier
     * @param eEth Address of the eEth
     * @param tokenOut Address of the main token
     * @param lockBox Address of the lock box
     * @param owner Address of the owner
     */
    function initialize(address liquifier, address eEth, address tokenOut, address lockBox, address owner)
        external
        initializer
    {
        __L1BaseSyncPool_init(tokenOut, lockBox, owner);
        __Ownable_init(owner);

        _setLiquifier(liquifier);
        _setEEth(eEth);
    }

    function initializeV2(address _liquidityPool) external onlyOwner {
        require(address(_liquidityPool) == address(0x00), "already initialized");
        
        liquidityPool = ILiquidityPool(_liquidityPool);
    }

    /**
     * @dev Get the liquifier address
     * @return The liquifier address
     */
    function getLiquifier() public view returns (address) {
        return address(_liquifier);
    }

    /**
     * @dev Get the eEth address
     * @return The eEth address
     */
    function getEEth() public view returns (address) {
        return address(_eEth);
    }

    /**
     * @dev Get the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @return The dummy token address
     */
    function getDummyToken(uint32 originEid) public view virtual returns (address) {
        return address(_dummyTokens[originEid]);
    }

    /**
     * @dev Set the liquifier address
     * @param liquifier The liquifier address
     */
    function setLiquifier(address liquifier) public onlyOwner {
        _setLiquifier(liquifier);
    }

    /**
     * @dev Set the eEth address
     * @param eEth The eEth address
     */
    function setEEth(address eEth) public onlyOwner {
        _setEEth(eEth);
    }

    /**
     * @dev Set the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @param dummyToken The dummy token address
     */
    function setDummyToken(uint32 originEid, address dummyToken) public onlyOwner {
        _setDummyToken(originEid, dummyToken);
    }

    /**
     * @dev Internal function to set the liquifier address
     * @param liquifier The liquifier address
     */
    function _setLiquifier(address liquifier) internal {
        _liquifier = ILiquifier(liquifier);

        emit LiquifierSet(liquifier);
    }

    /**
     * @dev Internal function to set the eEth address
     * @param eEth The eEth address
     */
    function _setEEth(address eEth) internal {
        _eEth = IERC20(eEth);

        emit EEthSet(eEth);
    }

    /**
     * @dev Internal function to set the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @param dummyToken The dummy token address
     */
    function _setDummyToken(uint32 originEid, address dummyToken) internal {
        _dummyTokens[originEid] = IDummyToken(dummyToken);

        emit DummyTokenSet(originEid, dummyToken);
    }

    /**
     * @dev Internal function to anticipate a deposit
     * Will mint the dummy tokens and deposit them to the L1 deposit pool
     * Will revert if:
     * - The token in is not ETH
     * - The dummy token is not set
     * @param originEid Origin EID
     * @param tokenIn Address of the token in
     * @param amountIn Amount in
     * @return actualAmountOut The actual amount of token received
     */
    function _anticipatedDeposit(uint32 originEid, bytes32, address tokenIn, uint256 amountIn, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmountOut)
    {
        if (tokenIn != Constants.ETH_ADDRESS) revert EtherfiL1SyncPoolETH__OnlyETH();

        IERC20 tokenOut = IERC20(getTokenOut());

        ILiquifier liquifier = _liquifier;
        IDummyToken dummyToken = _dummyTokens[originEid];

        if (address(dummyToken) == address(0)) revert EtherfiL1SyncPoolETH__UnsetDummyToken();

        uint256 balanceBefore = tokenOut.balanceOf(address(this));

        dummyToken.mint(address(this), amountIn);
        dummyToken.approve(address(liquifier), amountIn);

        liquifier.depositWithERC20(address(dummyToken), amountIn, address(0));

        uint256 eEthBalance = _eEth.balanceOf(address(this));

        _eEth.approve(address(tokenOut), eEthBalance);
        IWeEth(address(tokenOut)).wrap(eEthBalance);

        return tokenOut.balanceOf(address(this)) - balanceBefore;
    }

    /**
     * @dev Internal function to finalize a deposit
     * Will swap the dummy tokens for the actual ETH
     * Will revert if:
     * - The token in is not ETH
     * - The amount in is not equal to the value
     * - The dummy token is not set
     * @param originEid Origin EID
     * @param tokenIn Address of the token in
     * @param amountIn Amount in
     */
    function _finalizeDeposit(uint32 originEid, bytes32, address tokenIn, uint256 amountIn, uint256)
        internal
        virtual
        override
    {
        if (tokenIn != Constants.ETH_ADDRESS) revert EtherfiL1SyncPoolETH__OnlyETH();
        if (amountIn != msg.value) revert EtherfiL1SyncPoolETH__InvalidAmountIn();

        ILiquifier liquifier = _liquifier;
        IDummyToken dummyToken = _dummyTokens[originEid];

        if (address(dummyToken) == address(0)) revert EtherfiL1SyncPoolETH__UnsetDummyToken();

        uint256 dummyBalance = dummyToken.balanceOf(address(liquifier));
        uint256 ethBalance = address(this).balance;

        uint256 swapAmount = ethBalance > dummyBalance ? dummyBalance : ethBalance;

        liquifier.unwrapL2Eth{value: swapAmount}(address(dummyToken));

        dummyToken.burn(swapAmount);
    }

    /**
     * @dev Internal function called when a LZ message is received
     * @param origin Origin
     * @param guid Message GUID
     * @param message Message
     */
    function _lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address, bytes calldata)
        internal
        virtual
        override
    {
        (address tokenIn, uint256 amountIn, uint256 amountOut) = abi.decode(message, (address, uint256, uint256));

        uint256 actualAmountOut = _anticipatedDeposit(origin.srcEid, guid, tokenIn, amountIn, amountOut);

        // socialize native minting losses with the protocol
        if (actualAmountOut < amountOut) {

            // if the minting loss is higher than 50 bps, revert
            if (actualAmountOut < (amountOut * 995) / 1000) {
                revert("EtherfiL1SyncPoolETH: minting loss too high");
            }

            IERC20 tokenOut = IERC20(getTokenOut());
            uint256 balanceBefore = tokenOut.balanceOf(address(this));

            uint256 unbackedAmountWeETH = amountOut - actualAmountOut;
            uint256 unbackedAmountEETH = IWeEth(address(tokenIn)).getEETHByWeETH(unbackedAmountWeETH);
            liquidityPool.depositToSyncPool(unbackedAmountEETH);

            uint256 eEthBalance = _eEth.balanceOf(address(this));
            _eEth.approve(address(tokenOut), eEthBalance);
            IWeEth(address(tokenOut)).wrap(eEthBalance);

            uint256 additionalAmountOut = tokenOut.balanceOf(address(this)) - balanceBefore;

            actualAmountOut += additionalAmountOut;
        }

        _handleAnticipatedDeposit(origin.srcEid, guid, actualAmountOut, amountOut);
    }

}
