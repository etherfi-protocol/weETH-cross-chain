// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OFTAdapterUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTAdapterUpgradeable.sol";

contract EtherFiOFTAdapterUpgradeable is OFTAdapterUpgradeable {

    /**
     * @dev Constructor for EtherFiOFTAdapterUpgradeable
     * @param _token The address of the already deployed weETH token 
     * @param _lzEndpoint The LZ endpoint address
     */
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param _owner The contract owner
     * @param _delegate The LZ delegate
     */
    function initialize(address _owner, address _delegate) external virtual initializer {
        __Ownable_init(_owner);
        __OFTAdapter_init(_delegate);
    }

}
