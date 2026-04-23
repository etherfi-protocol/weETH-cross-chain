// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintablePausableERC20 is IERC20 {
    event TransferPaused();
    event TransferUnpaused();
    event TransferPausedUntil(address indexed user, uint256 until);
    event TransferPausedUntilCancelled(address indexed user);

    error TransferIsPaused();
    error TransferIsNotPaused();
    error TransferIsPausedUntil(address user, uint256 until);
    error TransferIsNotPausedUntil(address user);
    error InvalidUser();

    function mint(address account, uint256 amount) external;
    function pauseTransfer() external;
    function unpauseTransfer() external;
    function pauseTransferUntil(address user) external;
    function extendPauseTransferUntil(address user, uint256 duration) external;
    function cancelPauseTransferUntil(address user) external;
}
