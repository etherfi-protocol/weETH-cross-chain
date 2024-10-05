// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {OFTUpgradeable} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTUpgradeable.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import { RateLimiter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

/**
 * @title Mintable OFT
 * @dev An OFT token that can be minted by a minter.
 */
contract MintableOFTUpgradeable is RateLimiter, OFTUpgradeable, AccessControlUpgradeable, PausableUpgradeable, IMintableERC20 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Constructor for MintableOFT
     * @param endpoint The layer zero endpoint address
     */
    constructor(address endpoint) OFTUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param owner The owner of the token
     */
    function initialize(string memory name, string memory symbol, address owner) external virtual initializer {
        __OFT_init(name, symbol, owner);
        __Ownable_init(owner);

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkAndUpdateRateLimit(_dstEid, _amountLD);
        return super._debit(_amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        return super._credit(_to, _amountLD, 0);
    }

    /**
     * @dev Mint function that can only be called by a minter
     * @param _account The account to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_account, _amount);
    }
    
    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRateLimits(_rateLimitConfigs);
    }

    function updateTokenSymbol(string memory name_, string memory symbol_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC20Storage storage $ = getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

   function pauseBridge() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpauseBridge() public onlyOwner {
        _unpause();
    }

    function getERC20Storage() internal pure returns (ERC20Storage storage $) {
        bytes32 ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        assembly {
            $.slot := ERC20StorageLocation
        }
    }
}
