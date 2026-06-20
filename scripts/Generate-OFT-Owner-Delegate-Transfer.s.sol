// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

interface IOFTLike {
    function owner() external view returns (address);
    function endpoint() external view returns (address);
}

interface ILZEndpointLike {
    function delegates(address oapp) external view returns (address);
}

/// @dev Per-chain simulator. Lives outside the Script contract so it can
///      be invoked via try/catch (Foundry forbids `address(this)` in scripts).
contract OFTOwnerDelegateSimulator is GnosisHelpers {

    address public immutable expectedTimelock;

    constructor(address _timelock) {
        expectedTimelock = _timelock;
    }

    function simulateChain(
        string calldata name,
        string calldata rpcUrl,
        address oft,
        address safe,
        string calldata path
    ) external {
        vm.createSelectFork(rpcUrl);

        address endpointAddr = IOFTLike(oft).endpoint();

        require(
            IOFTLike(oft).owner() == safe,
            string.concat(name, ": pre-owner != safe")
        );
        require(
            ILZEndpointLike(endpointAddr).delegates(oft) == safe,
            string.concat(name, ": pre-delegate != safe")
        );

        executeGnosisTransactionBundle(path, safe);

        require(
            IOFTLike(oft).owner() == expectedTimelock,
            string.concat(name, ": post-owner != timelock")
        );
        require(
            ILZEndpointLike(endpointAddr).delegates(oft) == expectedTimelock,
            string.concat(name, ": post-delegate != timelock")
        );
    }
}

/// @notice Generates Gnosis Safe transaction bundles that transfer the
///         LayerZero `delegate` and the OFT `owner` to the L2 timelock,
///         for every chain whose OFT is currently owned by the controller
///         safe (verified on-chain 2026-05-22). After writing each bundle
///         this script forks the target chain and replays the bundle to
///         assert the post-state matches expectations.
///
///         Order matters: `setDelegate` must run before `transferOwnership`,
///         since both are `onlyOwner` and once the safe gives up ownership
///         any further `setDelegate` would have to be proposed through the
///         timelock (3 day delay).
contract TransferOFTOwnerAndDelegateToTimelock is Script, L2Constants, GnosisHelpers {

    /// @dev Returns primary + fallback RPCs for a chain. Empty slots are skipped.
    ///      Some public endpoints (zkSync, Unichain) intermittently fail TLS
    ///      handshakes; supply alternates so a single bad attempt is not fatal.
    function _rpcsFor(ConfigPerL2 memory c) internal pure returns (string[3] memory rpcs) {
        rpcs[0] = c.RPC_URL;
        bytes32 nameHash = keccak256(bytes(c.NAME));
        if (nameHash == keccak256(bytes("zksync"))) {
            rpcs[1] = "https://zksync.drpc.org";
            rpcs[2] = "https://1rpc.io/zksync2-era";
        } else if (nameHash == keccak256(bytes("unichain"))) {
            rpcs[1] = "https://unichain.drpc.org";
            rpcs[2] = "https://0xrpc.io/uni";
        } else if (nameHash == keccak256(bytes("hyperEVM"))) {
            rpcs[1] = "https://hyperliquid.drpc.org";
        }
    }

    function _targets() internal view returns (ConfigPerL2[15] memory) {
        return [
            BLAST,
            MODE,
            LINEA,
            BASE,
            BNB,
            MORPH,
            OP,
            SCROLL,
            ZKSYNC,
            SWELL,
            BERA,
            UNICHAIN,
            AVAX,
            SONIC,
            HYPEREVM
        ];
    }

    function run() public {
        ConfigPerL2[15] memory targets = _targets();

        string memory setDelegateData = iToHex(
            abi.encodeWithSignature("setDelegate(address)", L2_TIMELOCK)
        );
        string memory transferOwnershipData = iToHex(
            abi.encodeWithSignature("transferOwnership(address)", L2_TIMELOCK)
        );

        // Phase 1: write every JSON bundle. Fork-independent — must not be
        // blocked by an RPC failure during simulation.
        for (uint256 i = 0; i < targets.length; i++) {
            ConfigPerL2 memory c = targets[i];
            string memory oftHex = addressToHex(c.L2_OFT);
            string memory bundle = _getGnosisHeader(c.CHAIN_ID, c.L2_CONTRACT_CONTROLLER_SAFE);
            bundle = string(abi.encodePacked(
                bundle,
                _getGnosisTransaction(oftHex, setDelegateData, false),
                _getGnosisTransaction(oftHex, transferOwnershipData, true)
            ));
            vm.writeJson(bundle, string.concat("./output/", c.NAME, "-OFT-OwnerDelegate-ToTimelock.json"));
        }

        // Phase 2: simulate per chain via an external helper contract so a
        // single RPC failure cannot abort the run. Each chain gets up to
        // three RPC attempts (primary + two fallbacks) since some public
        // endpoints (zkSync, Unichain) are intermittent.
        OFTOwnerDelegateSimulator sim = new OFTOwnerDelegateSimulator(L2_TIMELOCK);

        uint256 ok;
        uint256 fail;
        uint256 skipped;
        for (uint256 i = 0; i < targets.length; i++) {
            ConfigPerL2 memory c = targets[i];
            string memory path = string.concat("./output/", c.NAME, "-OFT-OwnerDelegate-ToTimelock.json");

            // zkSync's non-EVM-equivalent block format causes vanilla
            // `forge`'s createSelectFork to fail across every public RPC.
            // The JSON is still written above; verify on chain after execution
            // (cast call <oft> "owner()", endpoint.delegates(oft)).
            if (keccak256(bytes(c.NAME)) == keccak256(bytes("zksync"))) {
                console.log("[SKIP] zksync simulation (forge fork incompatible); verify via cast post-execution");
                skipped++;
                continue;
            }

            string[3] memory rpcs = _rpcsFor(c);
            bool passed;
            string memory lastReason;
            for (uint256 r = 0; r < rpcs.length; r++) {
                if (bytes(rpcs[r]).length == 0) break;
                try sim.simulateChain(c.NAME, rpcs[r], c.L2_OFT, c.L2_CONTRACT_CONTROLLER_SAFE, path) {
                    passed = true;
                    break;
                } catch Error(string memory reason) {
                    lastReason = reason;
                } catch (bytes memory) {
                    lastReason = "non-string revert; likely RPC error";
                }
            }

            if (passed) {
                console.log("[OK]", c.NAME, "owner & delegate -> timelock");
                ok++;
            } else {
                console.log("[FAIL]", c.NAME, lastReason);
                fail++;
            }
        }

        // Phase 3: Ethereum mainnet. The L1 OFT adapter is a plain Ownable
        // owned by + delegated to the L1 controller safe; transfer both to the
        // 2-day operating timelock (the safe holds proposer+executor there).
        if (_runL1()) {
            ok++;
        } else {
            fail++;
        }

        console.log("Simulation summary: ok=", ok, "fail=", fail);
        console.log("                    skipped=", skipped);
        require(fail == 0, "one or more chain simulations failed");
    }

    /// @dev Writes and simulates the Ethereum mainnet bundle. Returns true if
    ///      the post-state simulation passed. Calldata targets the L1 operating
    ///      timelock — distinct from the L2_TIMELOCK used for the L2 bundles.
    function _runL1() internal returns (bool) {
        string memory setDelegateData = iToHex(
            abi.encodeWithSignature("setDelegate(address)", L1_OPERATING_TIMELOCK)
        );
        string memory transferOwnershipData = iToHex(
            abi.encodeWithSignature("transferOwnership(address)", L1_OPERATING_TIMELOCK)
        );
        string memory l1OftHex = addressToHex(L1_OFT_ADAPTER);
        string memory bundle = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);
        bundle = string(abi.encodePacked(
            bundle,
            _getGnosisTransaction(l1OftHex, setDelegateData, false),
            _getGnosisTransaction(l1OftHex, transferOwnershipData, true)
        ));
        string memory path = "./output/ethereum-OFT-OwnerDelegate-ToTimelock.json";
        vm.writeJson(bundle, path);

        OFTOwnerDelegateSimulator sim = new OFTOwnerDelegateSimulator(L1_OPERATING_TIMELOCK);
        try sim.simulateChain("ethereum", L1_RPC_URL, L1_OFT_ADAPTER, L1_CONTRACT_CONTROLLER, path) {
            console.log("[OK] ethereum owner & delegate -> timelock");
            return true;
        } catch Error(string memory reason) {
            console.log("[FAIL] ethereum", reason);
            return false;
        } catch (bytes memory) {
            console.log("[FAIL] ethereum non-string revert; likely RPC error");
            return false;
        }
    }
}
