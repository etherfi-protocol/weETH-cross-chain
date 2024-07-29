// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../utils/LayerZeroHelpers.sol";
import "../interfaces/INTTManager.sol";

contract transferNTT is Test, LayerZeroHelpers {

    address public NTT_MANAGER = 0x344169Cc4abE9459e77bD99D13AA8589b55b6174;
    address public SENDING_GNOSIS = 0x5f0E7A424d306e9E310be4f5Bb347216e473Ae55;
    address public RECEIVING_GNOSIS = 0xbe2cfe1a304B6497E6f64525D0017AbaB7a5E8Cb;

    function test_Transfer() public {
        vm.createSelectFork("https://mainnet.gateway.tenderly.co");

        vm.startPrank(SENDING_GNOSIS);

        INTTManager nttManager = INTTManager(NTT_MANAGER);

        bytes32 destinationBytes = _toBytes32(destinationAddress);

        console.logBytes32(destinationBytes);
    }

}