// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// OZ v5 ProxyAdmin surface (these admins expose upgradeAndCall + Ownable).
interface IProxyAdmin {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function upgradeAndCall(address proxy, address impl, bytes calldata data) external payable;
}

// Fork test for the native-minting upgrade-authority transfer on Ethereum and
// Optimism: move each ProxyAdmin from the controller Safe to the upgrade
// timelock, then prove the Safe can no longer upgrade. These are exactly the
// transactions encoded in:
//   output/ethereum-NativeMinting-ProxyAdmin-ToTimelock.json   (L1 controller Safe)
//   output/optimism-NativeMinting-ProxyAdmin-ToTimelock.json   (OP controller Safe)
//
// Run:
//   forge test --match-path test/NativeMintingUpgradeTimelock.t.sol -vv
//   (override forks with L1_FORK_RPC / OP_FORK_RPC if the defaults are throttled)
contract NativeMintingUpgradeTimelockTest is Test {
    // --- Ethereum ---
    address constant ETH_SAFE = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC; // L1 controller Safe
    address constant ETH_TIMELOCK = 0x9f26d4C958fD811A1F59B01B86Be7dFFc9d20761; // L1 upgrade timelock
    address constant L1_SYNCPOOL = 0xD789870beA40D056A4d26055d0bEFcC8755DA146;
    address constant L1_SYNCPOOL_PA = 0xDBf6bE120D4dc72f01534673a1223182D9F6261D;

    // --- Optimism ---
    address constant OP_SAFE = 0x764682c769CcB119349d92f1B63ee1c03d6AECFf; // OP controller Safe
    address constant OP_TIMELOCK = 0x851Dd540f4D2Ec78120De0a0cc87B21EdE5Df5C6; // canonical L2 timelock
    address constant OP_SYNCPOOL = 0xC9475e18E2C5C26EA6ADCD55fabE07920beA887e;
    address constant OP_SYNCPOOL_PA = 0xecA0b8088bF30eFd476F0a4e6b7e4B5D652b1ded;
    address constant OP_EXCHRATE = 0xAaE0d7D8147C9f2C39A0B19974f8E684fA2bbA6f;
    address constant OP_EXCHRATE_PA = 0x5ab0DCe5dbef9C0284fBdb34a8f8e3CF5216bA2c;
    address constant OP_RATELIMITER = 0x9685Ff6E421F163A9A2FbB831F28344f8e4a964a;
    address constant OP_RATELIMITER_PA = 0xc706AC2F5c9332890A7DC37837675ed3dd116416;

    // Transfer a ProxyAdmin from `safe` to `timelock` and prove the move revoked
    // the Safe's upgrade power.
    function _transferAndVerify(address pa, address proxy, address safe, address timelock) internal {
        assertEq(IProxyAdmin(pa).owner(), safe, "pre: admin owner is not the Safe");

        vm.prank(safe);
        IProxyAdmin(pa).transferOwnership(timelock);
        assertEq(IProxyAdmin(pa).owner(), timelock, "post: admin owner is not the timelock");

        // the Safe can no longer drive an upgrade (onlyOwner now reverts)
        vm.prank(safe);
        vm.expectRevert();
        IProxyAdmin(pa).upgradeAndCall(proxy, address(0xdEaD), "");
    }

    function test_ethereum_native_minting_admin_to_timelock() public {
        vm.createSelectFork(vm.envOr("L1_FORK_RPC", string("https://ethereum-rpc.publicnode.com")));
        // L1 receiver + dummy-token admins are already timelock-owned; only the
        // shared L1 sync pool admin still sits on the Safe.
        _transferAndVerify(L1_SYNCPOOL_PA, L1_SYNCPOOL, ETH_SAFE, ETH_TIMELOCK);
    }

    function test_optimism_native_minting_admins_to_timelock() public {
        vm.createSelectFork(vm.envOr("OP_FORK_RPC", string("https://optimism-rpc.publicnode.com")));
        _transferAndVerify(OP_SYNCPOOL_PA, OP_SYNCPOOL, OP_SAFE, OP_TIMELOCK);
        _transferAndVerify(OP_EXCHRATE_PA, OP_EXCHRATE, OP_SAFE, OP_TIMELOCK);
        _transferAndVerify(OP_RATELIMITER_PA, OP_RATELIMITER, OP_SAFE, OP_TIMELOCK);
    }
}
