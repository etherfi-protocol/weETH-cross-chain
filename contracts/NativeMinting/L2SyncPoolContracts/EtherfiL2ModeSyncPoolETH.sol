// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {L2ModeSyncPoolETHUpgradeable} from "./L2ModeSyncPoolETHUpgradeable.sol";

contract EtherfiL2ModeSyncPoolETH is L2ModeSyncPoolETHUpgradeable {
    constructor(address endpoint) L2ModeSyncPoolETHUpgradeable(endpoint) {
        _disableInitializers();
    }

    function initialize(
        address l2ExchangeRateProvider,
        address rateLimiter,
        address tokenOut,
        uint32 dstEid,
        address messenger,
        address receiver,
        address delegate
    ) external override initializer {
        __L2BaseSyncPool_init(l2ExchangeRateProvider, rateLimiter, tokenOut, dstEid, delegate);
        __BaseMessenger_init(messenger);
        __BaseReceiver_init(receiver);
        __Ownable_init(delegate);
    }
}
