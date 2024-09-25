// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWeEth {
    struct PermitInput {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event AdminChanged(address previousAdmin, address newAdmin);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BeaconUpgraded(address indexed beacon);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Upgraded(address indexed implementation);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function eETH() external view returns (address);
    function getEETHByWeETH(uint256 _weETHAmount) external view returns (uint256);
    function getImplementation() external view returns (address);
    function getRate() external view returns (uint256);
    function getWeETHByeETH(uint256 _eETHAmount) external view returns (uint256);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(address _liquidityPool, address _eETH) external;
    function liquidityPool() external view returns (address);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function owner() external view returns (address);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function proxiableUUID() external view returns (bytes32);
    function renounceOwnership() external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
    function unwrap(uint256 _weETHAmount) external returns (uint256);
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
    function wrap(uint256 _eETHAmount) external returns (uint256);
    function wrapWithPermit(uint256 _eETHAmount, PermitInput memory _permit) external returns (uint256);
}
