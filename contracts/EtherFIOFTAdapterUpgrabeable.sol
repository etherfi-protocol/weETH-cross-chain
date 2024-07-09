pragma solidity ^0.8.20;
// SPDX-License-Identifier: MIT

import { OFTAdapterUpgradeable } from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTAdapterUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract EtherFiOFTAdapterUpgradeable is OFTAdapterUpgradeable {
    constructor(
        address _token, // a deployed, already existing ERC20 token address
        address _layerZeroEndpoint // local endpoint address
        ) OFTAdapterUpgradeable(_token, _layerZeroEndpoint) {
        _disableInitializers();
    }

    function initialize(
        address _delegate,
        address _owner
    ) external initializer {
        __OFTAdapter_init(_delegate);
        __Ownable_init(_owner);
    }

}
