// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDummyToken} from "../../interfaces/IDummyToken.sol";
import {L1BaseSyncPoolUpgradeable, Constants} from "./layerzero-base/L1BaseSyncPoolUpgradeable.sol";
import {PausableUntil} from "../PausableUntil.sol";
import {ILiquifier} from "../../interfaces/ILiquifier.sol";
import {IWeEth} from "../../interfaces/IWeEth.sol";
import {IRoleRegistry} from "../../interfaces/IRoleRegistry.sol";

contract EtherfiL1SyncPoolETH is L1BaseSyncPoolUpgradeable, PausableUntil {
    error EtherfiL1SyncPoolETH__OnlyETH();
    error EtherfiL1SyncPoolETH__InvalidAmountIn();
    error EtherfiL1SyncPoolETH__UnsetDummyToken();
    error EtherfiL1SyncPoolETH__Paused();
    error EtherfiL1SyncPoolETH__AlreadyPaused();
    error EtherfiL1SyncPoolETH__NotPaused();

    ILiquifier private _liquifier;
    IERC20 private _eEth;

    mapping(uint32 => IDummyToken) private _dummyTokens;
    bool private _paused;

    IRoleRegistry public immutable _roleRegistry;

    event Paused();
    event Unpaused();
    event LiquifierSet(address liquifier);
    event EEthSet(address eEth);
    event DummyTokenSet(uint32 originEid, address dummyToken);
    error IncorrectCaller();

    modifier whenNotPaused() {
        _requireNotPaused();
        _requireNotPausedUntil();
        _;
    }

    modifier onlyAdmin() {
        _roleRegistry.onlyOperatingTimelock(msg.sender);
        _;
    }

    modifier onlyOperations() {
        _roleRegistry.onlyOperatingMultisig(msg.sender);
        _;
    }

    modifier onlyGuardian() {
        _roleRegistry.onlyGuardian(msg.sender);
        _;
    }

    /**
     * @dev Constructor for Etherfi L1 Sync Pool ETH
     * @param endpoint Address of the LayerZero endpoint
     */
    constructor(address endpoint, address roleRegistry) L1BaseSyncPoolUpgradeable(endpoint) {
        _roleRegistry = IRoleRegistry(roleRegistry);
    }

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
     * @dev Pause the contract
     */
    function pause() public onlyOperations {
        if (_paused) revert EtherfiL1SyncPoolETH__AlreadyPaused();
        _paused = true;
        emit Paused();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() public onlyOperations {
        if (!_paused) revert EtherfiL1SyncPoolETH__NotPaused();
        _paused = false;
        emit Unpaused();
    }

    function pauseUntil() public onlyGuardian {
        _pauseUntil();
    }

    function unpauseUntil() public onlyOperations {
        _unpauseUntil();
    }

    function setPauseUntilDuration(uint256 pauseUntilDuration) public onlyAdmin {
        _setPauseUntilDuration(pauseUntilDuration);
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
        whenNotPaused()
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

        liquifier.depositWithERC20(address(dummyToken), amountIn, 0, address(0));

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
        whenNotPaused()
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

    function _requireNotPaused() internal view {
        if (_paused) revert EtherfiL1SyncPoolETH__Paused();
    }
}
