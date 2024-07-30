// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OFTUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTAdapterUpgradeable.sol";

contract EtherFiOFTAdapterUpgradeable is OFTUpgradeable {

    /**
     * @dev Constructor for EtherFiOFTAdapterUpgradeable
     * @param endpoint The layer zero endpoint address
     */
    constructor(address endpoint) OFTUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param owner The owner/delegate of the token
     */
    function initialize(string memory name, string memory symbol, address owner) external virtual initializer {
        __OFT_init(name, symbol, owner);
        __Ownable_init(owner);
    }


}
