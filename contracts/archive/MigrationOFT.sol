// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title Migration OFT
 * @dev OFT with restricted functionality to assist in our OFT adatper migration.
 */
contract MigrationOFT is OFT {
    // Address of the deployed OFT address on mainnet
    address public immutable TARGET_OFT_ADAPTER;
    // Mainnet Endpoint ID
    uint32 public constant DST_EID = 30101;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _initialOwner,
        address _targetOFTAdapter
    ) OFT(_name, _symbol, _lzEndpoint, _initialOwner) Ownable(_initialOwner) { 
        if (_targetOFTAdapter == address(0)) {
            revert("MigrationOFT: target OFT adapter cannot be the zero address");
        }
        TARGET_OFT_ADAPTER = _targetOFTAdapter;
    }

    /**
    * @dev Sends a migration message to mainnet.
    * @param _amount The amount of tokens to be sent to the new OFT adaptor.
    * @notice The `msg.value` should be set to the cross-chain fee computed from `quoteMigrationMessage`.
    */
    function sendMigrationMessage(uint256 _amount) external payable onlyOwner {
        // Minting the amount of tokens to send cross-chain to this contract
        _mint(address(this), _amount);

        SendParam memory param = SendParam({
            dstEid: DST_EID,
            to: _toBytes32(TARGET_OFT_ADAPTER),
            amountLD: _amount,
            minAmountLD: _removeDust(_amount),
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = MessagingFee({
            nativeFee: msg.value,
            lzTokenFee: 0
        });

        // send migration message, set refund address to owner
        this.send{value: fee.nativeFee }(param, fee, msg.sender);
    }

    /**
     * @dev returns a quoted fee for the migration message
     * @param _amount The amount of tokens to be sent to the new OFT adaptor
     */
    function quoteMigrationMessage(uint256 _amount) public view returns (uint256) {
        // Minting the amount of tokens to send cross-chain to this contract
        SendParam memory param = SendParam({
            dstEid: DST_EID,
            to: _toBytes32(TARGET_OFT_ADAPTER),
            amountLD: _amount,
            minAmountLD: _removeDust(_amount),
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = this.quoteSend(param, false);

        return (fee.nativeFee * 3) / 2; // 1.5x the quoted fee
    }

    /**
     * @dev Converts an address to bytes32
     * @param addr The address to convert
     * @return The address as bytes32
     */
    function _toBytes32(address addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
