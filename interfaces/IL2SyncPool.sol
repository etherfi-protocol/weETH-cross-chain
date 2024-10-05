// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppCore.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

interface IL2SyncPool is IOAppCore {
    function deposit(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        returns (uint256 amountOut);

    function sync(address tokenIn, bytes calldata extraOptions, MessagingFee calldata fee)
        external
        payable
        returns (uint256 unsyncedAmountIn, uint256 unsyncedAmountOut);
}
