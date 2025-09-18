// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILayerZeroComposer} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {L1BaseReceiverUpgradeable} from "../layerzero-base/L1BaseReceiverUpgradeable.sol";
import {Constants} from "../../libraries/Constants.sol";

/**
 * @title L1 Hydra Receiver ETH
 * @notice L1 receiver contract for ETH from Hydra pools
 * @dev This contract receives messages from a Hydra alt chain messenger and forwards them to the L1 sync pool
 * It only supports ETH
 */
contract L1HydraReceiverETHUpgradeable is L1BaseReceiverUpgradeable, ILayerZeroComposer {

    address immutable STARGATE_OAPP;

    /**
     * @param stargate Address of the Stargate OApp `StargatePoolNative`
     */
    constructor(address stargate) {
        STARGATE_OAPP = stargate;

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
     * @dev Receive compose message from the LayerZero Endpoint
     * It is permissionless to send messages to this function via Stargate; Unexpected calls will result in ETH donations to `L1SyncPool`
     * @param _from Address of the sender, the Stargate L1 OApp
     * @param _guid Guid of the message
     * @param _message Compose message constructed on the source chain
     */
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {

        uint32 originEid = OFTComposeMsgCodec.srcEid(_message);
        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);
        bytes memory composeMessage = OFTComposeMsgCodec.composeMsg(_message);

        (uint256 amountOut) = abi.decode(composeMessage, (uint256));

        _forwardToL1SyncPool(
            originEid, bytes32(uint256(uint160(_from))), _guid, Constants.ETH_ADDRESS, amountLD, amountOut, amountLD
        );
    }

    /**
     * @dev In the case of utilizing the Stargate OApp, the message is sent from the Stargate OApp not the L2 sync pool
     */
    function _getAuthorizedL2Address(uint32 /*originEid*/) internal view virtual override returns (bytes32) {
        return _addressToBytes32(STARGATE_OAPP);
    }

    /**
     * @dev Convert an address to bytes32
     * @param _addr Address to convert
     * @return bytes32 representation of the address
     */
    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function onMessageReceived(bytes calldata message) external payable virtual override {}
    fallback() external payable {}
    receive() external payable {}
}
