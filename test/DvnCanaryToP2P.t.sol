// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

/// @dev Minimal surface of the LayerZero EndpointV2 config reader.
interface IEndpointConfig {
    function getConfig(address _oapp, address _lib, uint32 _eid, uint32 _configType)
        external
        view
        returns (bytes memory);
}

interface IOFTPeers {
    function peers(uint32 eid) external view returns (bytes32);
}

interface ILzReceiver {
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable;
}

/// @dev ULN config type 2 (CONFIG_TYPE_ULN).
struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

// Replays the exact queued 3CP bytes (timelock scheduleBatch -> delay -> executeBatch) on a fork
// of every chain in the swap, then asserts the resulting ULN config on BOTH the send and receive
// library of every in-scope pathway is a clean 4-of-4 at 45 confirmations, containing P2P and
// no longer containing Canary.
contract DvnCanaryToP2PTest is Test {
    using stdJson for string;

    uint32 constant CONFIG_TYPE_ULN = 2;
    uint64 constant EXPECTED_CONFIRMATIONS = 45;
    uint8 constant EXPECTED_REQUIRED_COUNT = 4;

    string json;

    function setUp() public {
        json = vm.readFile("test/fixtures/dvn-canary-to-p2p.json");
    }

    // One test per chain: a single test body replaying all 12 forks exhausts EVM memory.
    function test_01_ethereum() public { _check(0); }
    function test_02_base() public { _check(1); }
    function test_03_op() public { _check(2); }
    function test_04_bnb() public { _check(3); }
    function test_05_linea() public { _check(4); }
    function test_06_unichain() public { _check(5); }
    function test_07_avax() public { _check(6); }
    function test_08_hyperEVM() public { _check(7); }
    function test_09_plasma() public { _check(8); }
    function test_10_ink() public { _check(9); }
    function test_11_monad() public { _check(10); }
    function test_12_robinhood() public { _check(11); }

    function _check(uint256 i) internal {
        uint256 checked = _runChain(i);
        assertGt(checked, 0, "no pathways checked");
        emit log_named_uint("pathway configs asserted (send+receive)", checked);
    }

    function _base(uint256 i) internal pure returns (string memory) {
        return string.concat(".chains[", vm.toString(i), "]");
    }

    struct Cfg {
        string name;
        address safe;
        address timelock;
        address endpoint;
        address oft;
        address sendLib;
        address recvLib;
        address canary;
        address p2p;
        uint256 delaySec;
        address[] expected;
        uint256[] eids;
    }

    function _load(uint256 i) internal view returns (Cfg memory c) {
        string memory p = _base(i);
        c.name = json.readString(string.concat(p, ".name"));
        c.safe = json.readAddress(string.concat(p, ".safe"));
        c.timelock = json.readAddress(string.concat(p, ".timelock"));
        c.endpoint = json.readAddress(string.concat(p, ".endpoint"));
        c.oft = json.readAddress(string.concat(p, ".oft"));
        c.sendLib = json.readAddress(string.concat(p, ".sendLib"));
        c.recvLib = json.readAddress(string.concat(p, ".recvLib"));
        c.canary = json.readAddress(string.concat(p, ".canary"));
        c.p2p = json.readAddress(string.concat(p, ".p2p"));
        c.delaySec = json.readUint(string.concat(p, ".delaySec"));
        c.expected = json.readAddressArray(string.concat(p, ".expectedDVNs"));
        c.eids = json.readUintArray(string.concat(p, ".eids"));
    }

    function _runChain(uint256 i) internal returns (uint256 asserted) {
        string memory p = _base(i);
        string memory rpc = vm.envOr(
            json.readString(string.concat(p, ".rpcEnv")),
            json.readString(string.concat(p, ".rpcFallback"))
        );
        if (bytes(rpc).length == 0) {
            emit log_named_string("SKIP (no rpc)", json.readString(string.concat(p, ".name")));
            return 0;
        }
        vm.createSelectFork(rpc);
        assertEq(block.chainid, json.readUint(string.concat(p, ".chainId")), "wrong fork chainid");

        Cfg memory c = _load(i);

        // --- pre-state: every pathway must currently carry Canary, on both libs
        for (uint256 k = 0; k < c.eids.length; k++) {
            _assertContains(c, c.sendLib, uint32(c.eids[k]), c.canary, true, "pre send");
            _assertContains(c, c.recvLib, uint32(c.eids[k]), c.canary, true, "pre recv");
        }

        _replay(c, p);

        // --- post-state: clean 4-of-4, P2P in, Canary out, sorted, on both libs
        for (uint256 k = 0; k < c.eids.length; k++) {
            _assertFinal(c, c.sendLib, uint32(c.eids[k]), "send");
            _assertFinal(c, c.recvLib, uint32(c.eids[k]), "recv");
            asserted += 2;
        }

        // --- the bridge still works, and the send actually pays P2P
        _assertBridgeWorks(c, uint32(c.eids[0]));

        emit log_named_string("OK", c.name);
    }

    /// Post-swap: send weETH out and receive weETH in on a real fork, then prove from the
    /// `DVNFeePaid` event that the send paid the new DVN set. Config reads alone cannot show
    /// that LayerZero actually assigns and pays P2P at send time.
    function _assertBridgeWorks(Cfg memory c, uint32 dstEid) internal {
        address token = IOFT(c.oft).token();
        address sender = vm.addr(0x5e7d);
        uint256 amount = 1e15; // 0.001 weETH; a multiple of 1e12 so no shared-decimal dust is lost

        // ---- outbound
        vm.deal(sender, 100 ether);
        deal(token, sender, amount);
        vm.prank(sender);
        IERC20(token).approve(c.oft, amount);

        SendParam memory p = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(sender))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = IOFT(c.oft).quoteSend(p, false);
        assertGt(fee.nativeFee, 0, string.concat(c.name, ": quoteSend returned a zero fee"));

        uint256 beforeBal = IERC20(token).balanceOf(sender);
        vm.recordLogs();
        vm.prank(sender);
        IOFT(c.oft).send{value: fee.nativeFee}(p, fee, sender);

        assertEq(
            IERC20(token).balanceOf(sender),
            beforeBal - amount,
            string.concat(c.name, ": sender was not debited")
        );

        _assertPaidNewDvnSet(c, dstEid);

        // ---- inbound: endpoint-gated credit, proves the mint path still works post-swap
        address recipient = vm.addr(0xbabe);
        uint256 recipientBefore = IERC20(token).balanceOf(recipient);
        bytes32 srcPeer = IOFTPeers(c.oft).peers(dstEid);
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(recipient))), uint64(amount / 1e12));
        Origin memory origin = Origin({ srcEid: dstEid, sender: srcPeer, nonce: 1 });

        vm.prank(c.endpoint);
        ILzReceiver(c.oft).lzReceive(origin, keccak256("dvn-swap-test"), message, address(0), "");

        assertGt(
            IERC20(token).balanceOf(recipient),
            recipientBefore,
            string.concat(c.name, ": recipient was not credited on inbound")
        );
    }

    /// Scan the recorded logs for `DVNFeePaid(address[],address[],uint256[])` and assert the
    /// required set LayerZero actually billed is the post-swap set: P2P in, Canary out.
    function _assertPaidNewDvnSet(Cfg memory c, uint32 dstEid) internal {
        bytes32 topic = keccak256("DVNFeePaid(address[],address[],uint256[])");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != topic) continue;
            found = true;
            (address[] memory required, address[] memory optional, uint256[] memory fees) =
                abi.decode(logs[i].data, (address[], address[], uint256[]));

            string memory where =
                string.concat(c.name, " send to eid ", vm.toString(uint256(dstEid)), ": DVNFeePaid");

            assertEq(required.length, 4, string.concat(where, " required count != 4"));
            assertEq(optional.length, 0, string.concat(where, " has optional DVNs"));
            assertEq(fees.length, 4, string.concat(where, " fee count != 4"));

            bool sawP2P;
            for (uint256 j = 0; j < required.length; j++) {
                assertEq(required[j], c.expected[j], string.concat(where, " DVN mismatch"));
                assertTrue(required[j] != c.canary, string.concat(where, " still pays Canary"));
                if (required[j] == c.p2p) sawP2P = true;
                assertGt(fees[j], 0, string.concat(where, " a DVN was paid zero"));
            }
            assertTrue(sawP2P, string.concat(where, " did not pay P2P"));
        }
        assertTrue(found, string.concat(c.name, ": no DVNFeePaid event in the send transaction"));
    }

    /// Replays the literal queued bytes as the real proposer Safe.
    function _replay(Cfg memory c, string memory p) internal {
        bytes memory scheduleData = json.readBytes(string.concat(p, ".scheduleData"));
        bytes memory executeData = json.readBytes(string.concat(p, ".executeData"));

        vm.startPrank(c.safe);
        (bool okS,) = c.timelock.call(scheduleData);
        require(okS, string.concat(c.name, ": scheduleBatch reverted"));

        // execute must not be possible before the delay elapses
        (bool early,) = c.timelock.call(executeData);
        require(!early, string.concat(c.name, ": executeBatch succeeded before delay"));

        vm.warp(block.timestamp + c.delaySec + 1);
        (bool okE,) = c.timelock.call(executeData);
        require(okE, string.concat(c.name, ": executeBatch reverted"));
        vm.stopPrank();
    }

    function _read(address endpoint, address oft, address lib, uint32 eid)
        internal
        view
        returns (UlnConfig memory u)
    {
        bytes memory raw = IEndpointConfig(endpoint).getConfig(oft, lib, eid, CONFIG_TYPE_ULN);
        u = abi.decode(raw, (UlnConfig));
    }

    function _assertContains(Cfg memory c, address lib, uint32 eid, address dvn, bool want, string memory tag)
        internal
        view
    {
        UlnConfig memory u = _read(c.endpoint, c.oft, lib, eid);
        bool found;
        for (uint256 j = 0; j < u.requiredDVNs.length; j++) {
            if (u.requiredDVNs[j] == dvn) found = true;
        }
        require(found == want, string.concat(c.name, " ", tag, ": DVN presence mismatch"));
    }

    function _assertFinal(Cfg memory c, address lib, uint32 eid, string memory tag) internal view {
        UlnConfig memory u = _read(c.endpoint, c.oft, lib, eid);
        address[] memory expected = c.expected;
        address canary = c.canary;
        address p2p = c.p2p;
        string memory where = string.concat(c.name, " ", tag, " eid ", vm.toString(uint256(eid)));

        require(u.confirmations == EXPECTED_CONFIRMATIONS, string.concat(where, ": confirmations != 45"));
        require(u.requiredDVNCount == EXPECTED_REQUIRED_COUNT, string.concat(where, ": requiredDVNCount != 4"));
        require(u.optionalDVNCount == 0, string.concat(where, ": optionalDVNCount != 0"));
        require(u.optionalDVNThreshold == 0, string.concat(where, ": optionalDVNThreshold != 0"));
        require(u.requiredDVNs.length == 4, string.concat(where, ": requiredDVNs length != 4"));
        require(u.optionalDVNs.length == 0, string.concat(where, ": optionalDVNs not empty"));

        bool sawP2P;
        for (uint256 j = 0; j < 4; j++) {
            require(u.requiredDVNs[j] == expected[j], string.concat(where, ": DVN mismatch at index"));
            require(u.requiredDVNs[j] != canary, string.concat(where, ": Canary still present"));
            if (u.requiredDVNs[j] == p2p) sawP2P = true;
            // LayerZero reverts LZ_ULN_Unsorted on an unsorted required array
            if (j > 0) {
                require(
                    uint160(u.requiredDVNs[j - 1]) < uint160(u.requiredDVNs[j]),
                    string.concat(where, ": DVNs not sorted ascending")
                );
            }
        }
        require(sawP2P, string.concat(where, ": P2P missing"));
    }
}
