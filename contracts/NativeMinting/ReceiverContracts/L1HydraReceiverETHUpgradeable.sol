// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILayerZeroComposer} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import {L1BaseReceiverUpgradeable} from "../LayerZeroBaseContracts/L1BaseReceiverUpgradeable.sol";
import {Constants} from "../../libraries/Constants.sol";

/**
 * @title L1 Hydra Receiver ETH
 * @notice L1 receiver contract for ETH from hydra pools
 * @dev This contract receives messages from a hydra alt chain messenger and forwards them to the L1 sync pool
 * It only supports ETH
 */
contract L1HydraReceiverETHUpgradeable is L1BaseReceiverUpgradeable, ILayerZeroComposer {
    error L1HydraReceiverETH__OnlyETH();

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer for L1 Hydra Receiver ETH
     * @param l1SyncPool Address of the L1 sync pool
     * @param messenger Address of the messenger contract
     * @param owner Address of the owner
     */
    function initialize(address l1SyncPool, address messenger, address owner) external initializer {

        __Ownable_init(owner);
        __L1BaseReceiver_init(l1SyncPool, messenger);
    }

    /**
     * @dev receive compose message from the LayerZero Endpoint
     */
    function lzCompose(
        address _from,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) external payable {

        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);
        bytes memory composeMessage = OFTComposeMsgCodec.composeMsg(_message);

        (uint32 originEid, bytes32 guid, address tokenIn, , uint256 amountOut) =
            abi.decode(composeMessage, (uint32, bytes32, address, uint256, uint256));

        if (tokenIn != Constants.ETH_ADDRESS) revert L1HydraReceiverETH__OnlyETH();

        _forwardToL1SyncPool(
            originEid, bytes32(uint256(uint160(_from))), guid, tokenIn, amountLD, amountOut, amountLD
        );
    }

    function onMessageReceived(bytes calldata message) external payable virtual override {}
}
