// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OFTUpgradeable } from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/OFTUpgradeable.sol";
import { RateLimiter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import { CustomPausableUpgradeable } from "./CustomPausableUpgradeable.sol";
import { IMintableERC20 } from "../interfaces/IMintableERC20.sol";

/**
 * @title Pausable Mintable OFT
 * @dev This contract extends the OFT contract to allow for minting by a minter and pausing of OFT functionality {nativeMinting, crossChainSends, crossChainReceives}
 */
contract PausableMintableOFTUpgradeable is RateLimiter, OFTUpgradeable, AccessControlUpgradeable, IMintableERC20, CustomPausableUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Pauses all OFT functionality {nativeMinting, crossChainSends, crossChainReceives}
    uint8 public constant PAUSED_CROSS_CHAIN = 0;
    // Pauses all balance changes effectively making the token non-transferable, non-mintable, and non-burnable
    uint8 public constant PAUSED_MOVEMENT = 1;

    /**
     * @dev Constructor for PausableMintableOFTUpgradeable
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
    ) internal virtual override whenNotPaused(PAUSED_CROSS_CHAIN) returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkAndUpdateRateLimit(_dstEid, _amountLD);
        return super._debit(_amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override whenNotPaused(PAUSED_CROSS_CHAIN) returns (uint256 amountReceivedLD) {
        return super._credit(_to, _amountLD, 0);
    }

    function _update(
        address from, 
        address to, 
        uint256 value
    ) internal virtual override whenNotPaused(PAUSED_MOVEMENT) {
        super._update(from, to, value);
    }

    /**
     * @dev Mint function that can only be called by a minter
     * @param _account The account to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _credit(_account, _amount, 0);
    }
    
    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRateLimits(_rateLimitConfigs);
    }

    function updateTokenSymbol(string memory name_, string memory symbol_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC20Storage storage $ = getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

    function pauseCrossChain() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause(PAUSED_CROSS_CHAIN);
    }

    function unpauseCrossChain() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause(PAUSED_CROSS_CHAIN);
    }

    function pauseMovement() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause(PAUSED_MOVEMENT);
    }

    function unpauseMovement() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause(PAUSED_MOVEMENT);
    }

    // // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))

    function getERC20Storage() internal pure returns (ERC20Storage storage $) {
        bytes32 ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        assembly {
            $.slot := ERC20StorageLocation
        }
    }
}
