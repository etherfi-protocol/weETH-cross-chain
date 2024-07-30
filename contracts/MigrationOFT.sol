// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

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
        address _delegate, 
        address _initialOwner,
        address _targetOFTAdapter
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_initialOwner) { 
        TARGET_OFT_ADAPTER = _targetOFTAdapter;
    }

    /**
     * @dev sends a migration message to mainnet
     * @param _amount The amount of tokens to be sent to the new OFT adaptor
     */
    function sendMigrationMessage(uint256 _amount) external onlyOwner {
        // Minting the amount amount of tokens to migrate to the owner
        _mint(this.owner(), _amount);

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

        // send migration message, set refund address to owner
        this.send{value: fee.nativeFee }(param, fee, this.owner());
    }

    function _toBytes32(address addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
