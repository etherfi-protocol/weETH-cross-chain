// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";

interface ITimelock {
    function getMinDelay() external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
}

interface IOwned {
    function owner() external view returns (address);
}

/**
 * @notice Builds the timelock batches that upgrade one weETH OFT (or the Ethereum adapter) to the OFT controls
 * implementation and hand out the new roles. Everything comes from live state, never from a static list:
 * - the timelocks are the live owners of the ProxyAdmin and of the OFT,
 * - the proposer is the first address in registry/oft-controls.json that holds PROPOSER_ROLE on that timelock,
 * - a role is granted only when the holder does not hold it now, so no call is a no-op.
 *
 * Needs the implementation from DeployImpl.s.sol:
 *   TARGET_CHAIN=base OFT_CONTROLS_IMPL=0x... forge script scripts/oft-controls/UpgradeBatch.s.sol --rpc-url <rpc>
 *
 * Writes Safe bundles to output/oft-controls/<target>-<batch>-{schedule,execute}.json. When the ProxyAdmin and the
 * OFT share a timelock (every L2) the upgrade and the role calls go in one batch. When they differ (Ethereum) the
 * upgrade is one batch and the role calls are a second batch to schedule after the upgrade executes.
 *
 * GUARDIAN=0x... overrides the guardian from the policy file (for fork runs). tools/anvil-oft-controls.sh pushes
 * the bundles through the real timelocks on anvil forks and checks the result.
 */
contract UpgradeBatch is Script, GnosisHelpers {
    struct Call {
        address target;
        bytes data;
        string note;
    }

    struct Target {
        string name;
        string chainId;
        address oft;
        address proxyAdmin;
        address impl;
        bool adapter;
    }

    // L2 role ids (Solady EnumerableRoles) on EtherfiOFTUpgradeable
    uint256 internal constant MINTER = 1;
    uint256 internal constant PAUSER = 2;
    uint256 internal constant UNPAUSER = 3;
    uint256 internal constant BLACKLISTER = 4;
    uint256 internal constant WHITELISTER = 5;
    uint256 internal constant PAUSER_UNTIL = 6;

    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    Target internal target;
    string internal policy;
    Call[] internal upgradeCalls;
    Call[] internal roleCalls;
    uint256 internal pauseDuration;

    function run() external {
        _load();
        _preflight();
        _buildCalls();

        address upgradeTimelock = IOwned(target.proxyAdmin).owner();
        address roleTimelock = IOwned(target.oft).owner();
        vm.createDir("output/oft-controls", true);

        if (upgradeTimelock == roleTimelock) {
            Call[] memory all = new Call[](upgradeCalls.length + roleCalls.length);
            for (uint256 i = 0; i < upgradeCalls.length; i++) all[i] = upgradeCalls[i];
            for (uint256 i = 0; i < roleCalls.length; i++) all[upgradeCalls.length + i] = roleCalls[i];
            _batch("upgrade", upgradeTimelock, all);
        } else {
            _batch("upgrade", upgradeTimelock, _copy(upgradeCalls));
            if (roleCalls.length != 0) _batch("roles", roleTimelock, _copy(roleCalls));
        }

    }

    // ---------------------------------------------------------------------------------------------
    // inputs
    // ---------------------------------------------------------------------------------------------

    function _load() internal {
        string memory name = vm.envString("TARGET_CHAIN");
        string memory json = vm.readFile("registry/chains.json");
        string memory p = string.concat(".", name);
        target.name = name;
        target.chainId = vm.parseJsonString(json, string.concat(p, ".CHAIN_ID"));
        target.oft = vm.parseJsonAddress(json, string.concat(p, ".OFT"));
        target.proxyAdmin = vm.parseJsonAddress(json, string.concat(p, ".PROXY_ADMIN"));
        target.impl = vm.envAddress("OFT_CONTROLS_IMPL");
        target.adapter = keccak256(bytes(name)) == keccak256("ethereum");
        policy = vm.readFile("registry/oft-controls.json");
        pauseDuration = vm.parseJsonUint(policy, ".pauseUntilDuration");
    }

    /// @dev Policy value for a role: the target's own entry wins, then the default. Empty means unset.
    function _holder(string memory role) internal view returns (address) {
        string memory override_ = string.concat(".chains.", target.name, ".", role);
        string memory key = vm.keyExistsJson(policy, override_) ? override_ : string.concat(".defaults.", role);
        string memory value = vm.parseJsonString(policy, key);
        return bytes(value).length == 0 ? address(0) : vm.parseAddress(value);
    }

    function _guardian() internal view returns (address) {
        address fromEnv = vm.envOr("GUARDIAN", address(0));
        return fromEnv != address(0) ? fromEnv : _holder("guardian");
    }

    // ---------------------------------------------------------------------------------------------
    // checks on live state
    // ---------------------------------------------------------------------------------------------

    function _preflight() internal view {
        require(target.impl.code.length != 0, "no code at OFT_CONTROLS_IMPL: run DeployImpl first");
        address admin = address(uint160(uint256(vm.load(target.oft, bytes32(uint256(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))))));
        require(admin == target.proxyAdmin, "registry PROXY_ADMIN is not the proxy's admin");
        address current = address(uint160(uint256(vm.load(target.oft, IMPLEMENTATION_SLOT))));
        require(current != target.impl, "already on this implementation");
        require(IOwned(target.proxyAdmin).owner().code.length != 0, "ProxyAdmin owner is not a timelock contract");
        require(IOwned(target.oft).owner().code.length != 0, "OFT owner is not a timelock contract");

        (bool ok, bytes memory ret) = target.impl.staticcall(abi.encodeWithSignature("endpoint()"));
        require(ok, "implementation has no endpoint()");
        (bool ok2, bytes memory ret2) = target.oft.staticcall(abi.encodeWithSignature("endpoint()"));
        require(ok2 && keccak256(ret) == keccak256(ret2), "implementation endpoint differs from the live OFT");
    }

    // ---------------------------------------------------------------------------------------------
    // calls
    // ---------------------------------------------------------------------------------------------

    function _buildCalls() internal {
        upgradeCalls.push(
            Call(
                target.proxyAdmin,
                abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", target.oft, target.impl, bytes("")),
                "ProxyAdmin.upgradeAndCall to the controls implementation"
            )
        );

        // A guardian pause needs a duration before it works. The call is not a no-op until the new code runs.
        roleCalls.push(
            Call(
                target.oft,
                abi.encodeWithSignature("setPauseUntilDuration(uint256)", pauseDuration),
                "setPauseUntilDuration"
            )
        );

        _grantMinters();
        _grant(_holder("pauser"), PAUSER, keccak256("PAUSER_ROLE"), "PAUSER");
        _grant(_holder("unpauser"), UNPAUSER, keccak256("UNPAUSER_ROLE"), "UNPAUSER");
        _grant(_guardian(), PAUSER_UNTIL, keccak256("PAUSER_UNTIL_ROLE"), "PAUSER_UNTIL (guardian)");
        _grant(_holder("blacklister"), BLACKLISTER, keccak256("BLACKLISTER_ROLE"), "BLACKLISTER");
        _grant(_holder("whitelister"), WHITELISTER, keccak256("WHITELISTER_ROLE"), "WHITELISTER");
    }

    function _grant(address holder, uint256 id, bytes32 ozRole, string memory label) internal {
        if (holder == address(0)) {
            console.log("SKIP %s: not set in registry/oft-controls.json", label);
            return;
        }
        if (_holds(holder, id, ozRole)) {
            console.log("KEEP %s %s: already holds it", label, holder);
            return;
        }
        bytes memory data = target.adapter
            ? abi.encodeWithSignature("grantRole(bytes32,address)", ozRole, holder)
            : abi.encodeWithSignature("setRole(address,uint256,bool)", holder, id, true);
        roleCalls.push(Call(target.oft, data, string.concat("grant ", label)));
        console.log("GRANT %s %s", label, holder);
    }

    /// @dev The policy lists the minters to carry over. A legacy OFT only carries over a minter that holds the role
    /// today, so a stale policy entry cannot hand out a role nobody has.
    function _grantMinters() internal {
        address[] memory minters = vm.parseJsonAddressArray(policy, string.concat(".chains.", target.name, ".minters"));
        bytes32 ozMinter = keccak256("MINTER_ROLE");
        for (uint256 i = 0; i < minters.length; i++) {
            bool heldNow = _staticBool(abi.encodeWithSignature("hasRole(bytes32,address)", ozMinter, minters[i]));
            if (_isLegacy() && !heldNow) {
                console.log("SKIP MINTER %s: policy lists it but it does not hold MINTER_ROLE today", minters[i]);
                continue;
            }
            _grant(minters[i], MINTER, ozMinter, "MINTER");
        }
    }

    /// @dev A legacy OFT uses OpenZeppelin roles and has no roleHolders().
    function _isLegacy() internal view returns (bool) {
        if (target.adapter) return false;
        (bool ok, ) = target.oft.staticcall(abi.encodeWithSignature("roleHolders(uint256)", uint256(1)));
        return !ok;
    }

    /// @dev Whether `holder` holds the role under the role system the OFT has right now. A legacy OpenZeppelin OFT
    /// has no Solady roles, so it reads false and the grant is emitted: its roles do not carry over the upgrade.
    function _holds(address holder, uint256 id, bytes32 ozRole) internal view returns (bool) {
        if (target.adapter) return _staticBool(abi.encodeWithSignature("hasRole(bytes32,address)", ozRole, holder));
        return _staticBool(abi.encodeWithSignature("hasRole(address,uint256)", holder, id));
    }

    function _staticBool(bytes memory data) internal view returns (bool) {
        (bool ok, bytes memory ret) = target.oft.staticcall(data);
        return ok && ret.length == 32 && abi.decode(ret, (bool));
    }

    // ---------------------------------------------------------------------------------------------
    // timelock batches
    // ---------------------------------------------------------------------------------------------

    function _copy(Call[] storage src) internal view returns (Call[] memory out) {
        out = new Call[](src.length);
        for (uint256 i = 0; i < src.length; i++) out[i] = src[i];
    }

    function _batch(string memory name, address timelock, Call[] memory calls) internal {
        address[] memory targets = new address[](calls.length);
        uint256[] memory values = new uint256[](calls.length);
        bytes[] memory payloads = new bytes[](calls.length);
        console.log("---- batch %s on timelock %s (%s calls)", name, timelock, calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            targets[i] = calls[i].target;
            payloads[i] = calls[i].data;
            console.log("  %s: %s", i + 1, calls[i].note);
        }

        uint256 delay = ITimelock(timelock).getMinDelay();
        bytes32 salt = keccak256(abi.encodePacked("oft-controls-v1-", target.name, "-", name));
        address proposer = _pick(timelock, PROPOSER_ROLE);
        address executor = ITimelock(timelock).hasRole(EXECUTOR_ROLE, address(0)) ? proposer : _pick(timelock, EXECUTOR_ROLE);
        console.log("  delay %s s, proposer %s, executor %s", delay, proposer, executor);

        bytes memory schedule = abi.encodeCall(ITimelock.scheduleBatch, (targets, values, payloads, bytes32(0), salt, delay));
        bytes memory execute = abi.encodeCall(ITimelock.executeBatch, (targets, values, payloads, bytes32(0), salt));
        string memory base = string.concat("output/oft-controls/", target.name, "-", name);
        _write(string.concat(base, "-schedule.json"), proposer, timelock, schedule);
        _write(string.concat(base, "-execute.json"), executor, timelock, execute);
    }

    function _pick(address timelock, bytes32 role) internal view returns (address) {
        address[] memory candidates = vm.parseJsonAddressArray(policy, ".proposers");
        for (uint256 i = 0; i < candidates.length; i++) {
            if (ITimelock(timelock).hasRole(role, candidates[i])) return candidates[i];
        }
        revert(string.concat("no address in registry/oft-controls.json proposers holds the role on timelock ", vm.toString(timelock)));
    }

    function _write(string memory file, address safe, address to, bytes memory data) internal {
        string memory json = _getGnosisHeader(target.chainId, safe);
        json = string.concat(json, _getGnosisTransaction(addressToHex(to), iToHex(data), true));
        vm.writeJson(json, file);
    }
}
