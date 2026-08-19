// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/native-minting/EtherfiL1SyncPoolETH.sol";

// Minimal OZ v5 ProxyAdmin surface (on-chain admin exposes upgradeAndCall, not upgrade).
interface IProxyAdmin {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function upgradeAndCall(address proxy, address impl, bytes calldata data) external payable;
}

// OZ TimelockController surface used to drive an upgrade once the admin is the timelock.
interface ITimelock {
    function getMinDelay() external view returns (uint256);
    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt, uint256 delay) external;
    function execute(address target, uint256 value, bytes calldata payload, bytes32 predecessor, bytes32 salt) external payable;
}

// Fork test proving the L1 weETH sync pool upgrade path works end-to-end:
// rebuild the current implementation, push it through the live ProxyAdmin (owned
// by the L1 controller Safe), and assert storage + access control are intact.
//
// Run: forge test --match-path test/L1SyncPoolUpgrade.t.sol -vvv
//   (override the fork RPC with L1_FORK_RPC=<url> if the default is rate-limited)
contract L1SyncPoolUpgradeTest is Test {
    address constant SYNC_POOL = 0xD789870beA40D056A4d26055d0bEFcC8755DA146;
    address constant PROXY_ADMIN = 0xDBf6bE120D4dc72f01534673a1223182D9F6261D;
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    // EtherfiL1SyncPoolETH takes (endpoint, roleRegistry) and stores the registry as an
    // immutable, so it is baked into the runtime bytecode. This is the value the deployed
    // implementation 0x5d310451… actually carries — verified with
    //   cast call 0xD789870beA40D056A4d26055d0bEFcC8755DA146 "_roleRegistry()(address)"
    // Passing anything else would make the rebuilt bytecode diverge from the live one.
    address constant ROLE_REGISTRY = 0x62247D29B4B9BECf4BB73E0c722cf6445cfC7cE9;
    // The timelock that owns the sync pool today (owner()); 10-day delay.
    address constant OWNER_TIMELOCK = 0x9f26d4C958fD811A1F59B01B86Be7dFFc9d20761;
    // Governance Safe (6-of-10) holding PROPOSER + EXECUTOR on OWNER_TIMELOCK.
    address constant GOV_GNOSIS = 0xcdd57D11476c22d265722F68390b036f3DA48c21;
    // EIP-1967 implementation slot
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IProxyAdmin proxyAdmin = IProxyAdmin(PROXY_ADMIN);
    EtherfiL1SyncPoolETH pool = EtherfiL1SyncPoolETH(SYNC_POOL);

    function setUp() public {
        vm.createSelectFork(vm.envOr("L1_FORK_RPC", string("https://ethereum-rpc.publicnode.com")));
    }

    function _impl() internal view returns (address) {
        return address(uint160(uint256(vm.load(SYNC_POOL, IMPL_SLOT))));
    }

    function test_upgrade_preserves_state_and_access_control() public {
        // snapshot pre-upgrade state
        address oldImpl = _impl();
        address admin = proxyAdmin.owner();
        address owner_ = pool.owner();
        address liquifier = pool.getLiquifier();
        address eeth = pool.getEEth();
        address tokenOut = pool.getTokenOut();
        address lockBox = pool.getLockBox();
        uint256 unbacked = pool.getTotalUnbackedTokens();

        emit log_named_address("proxy admin owner (upgrade authority)", admin);
        emit log_named_address("current implementation", oldImpl);

        // rebuild the current implementation
        EtherfiL1SyncPoolETH newImpl = new EtherfiL1SyncPoolETH(LZ_ENDPOINT, ROLE_REGISTRY);
        assertTrue(address(newImpl) != oldImpl, "fresh impl collided with old");

        // a non-owner must not be able to upgrade
        vm.prank(address(0xBAD));
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(SYNC_POOL, address(newImpl), "");
        assertEq(_impl(), oldImpl, "impl changed on unauthorized call");

        // the ProxyAdmin owner (L1 controller Safe) performs the upgrade
        vm.prank(admin);
        proxyAdmin.upgradeAndCall(SYNC_POOL, address(newImpl), "");

        // implementation switched
        assertEq(_impl(), address(newImpl), "impl slot not updated");

        // storage preserved across the upgrade
        assertEq(pool.owner(), owner_, "owner changed");
        assertEq(pool.getLiquifier(), liquifier, "liquifier changed");
        assertEq(pool.getEEth(), eeth, "eEth changed");
        assertEq(pool.getTokenOut(), tokenOut, "tokenOut changed");
        assertEq(pool.getLockBox(), lockBox, "lockBox changed");
        assertEq(pool.getTotalUnbackedTokens(), unbacked, "unbacked tokens changed");
    }

    // Proves the requested change: move upgrade authority from the controller
    // Safe to the owner timelock, then show the Safe can no longer upgrade while
    // the timelock can (schedule -> wait minDelay -> execute), state preserved.
    function test_transfer_admin_to_timelock_then_upgrade_via_timelock() public {
        address admin = proxyAdmin.owner();

        // 1. Move ProxyAdmin ownership to the timelock (the 3CP tx), if it has not already
        //    happened. On mainnet today it has: owner() is already OWNER_TIMELOCK. Keeping this
        //    conditional lets the test assert the same end state whether it runs against a fork
        //    from before or after that migration.
        if (admin != OWNER_TIMELOCK) {
            vm.prank(admin);
            proxyAdmin.transferOwnership(OWNER_TIMELOCK);
        }
        assertEq(proxyAdmin.owner(), OWNER_TIMELOCK, "admin not on the timelock");

        // 2. A non-timelock caller cannot upgrade.
        EtherfiL1SyncPoolETH newImpl = new EtherfiL1SyncPoolETH(LZ_ENDPOINT, ROLE_REGISTRY);
        vm.prank(GOV_GNOSIS); // proposer on the timelock, but not the ProxyAdmin owner
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(SYNC_POOL, address(newImpl), "");
        assertTrue(_impl() != address(newImpl), "non-owner upgrade should have reverted");

        // 3. The timelock can upgrade, driven by the governance Safe.
        address owner_ = pool.owner();
        uint256 unbacked = pool.getTotalUnbackedTokens();
        bytes memory up = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)", SYNC_POOL, address(newImpl), bytes("")
        );
        uint256 delay = ITimelock(OWNER_TIMELOCK).getMinDelay();

        vm.prank(GOV_GNOSIS);
        ITimelock(OWNER_TIMELOCK).schedule(PROXY_ADMIN, 0, up, bytes32(0), bytes32(0), delay);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(GOV_GNOSIS);
        ITimelock(OWNER_TIMELOCK).execute(PROXY_ADMIN, 0, up, bytes32(0), bytes32(0));

        assertEq(_impl(), address(newImpl), "timelock upgrade did not take effect");
        assertEq(pool.owner(), owner_, "owner changed");
        assertEq(pool.getTotalUnbackedTokens(), unbacked, "state changed");
    }

    // Diagnostic: characterize how the repo-rebuilt implementation differs from
    // the deployed one. A tail-only difference is just CBOR metadata (benign);
    // an earlier divergence means real source/compiler drift.
    function test_diagnostic_rebuilt_vs_onchain_bytecode() public {
        bytes memory onchain = _impl().code;
        bytes memory rebuilt = address(new EtherfiL1SyncPoolETH(LZ_ENDPOINT, ROLE_REGISTRY)).code;
        emit log_named_uint("on-chain impl code length", onchain.length);
        emit log_named_uint("rebuilt  impl code length", rebuilt.length);

        uint256 min = onchain.length < rebuilt.length ? onchain.length : rebuilt.length;
        uint256 firstDiff = min;
        for (uint256 i = 0; i < min; i++) {
            if (onchain[i] != rebuilt[i]) {
                firstDiff = i;
                break;
            }
        }
        emit log_named_uint("first differing byte offset", firstDiff);
        emit log_named_uint("identical-prefix as % of shorter", min == 0 ? 0 : (firstDiff * 100) / min);
        emit log_string(
            firstDiff >= min
                ? "prefixes identical up to min length -> difference is trailing metadata only (benign)"
                : "divergence before the tail -> source/compiler settings differ from the deployed version"
        );
    }
}
