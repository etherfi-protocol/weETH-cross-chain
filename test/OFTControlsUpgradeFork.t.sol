// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {SendParam, OFTReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";

import {EtherfiOFTUpgradeable} from "../contracts/EtherfiOFTUpgradeable.sol";
import {EtherfiOFTAdapterUpgradeable} from "../contracts/EtherFiOFTAdapterUpgradeable.sol";
import {OFTControls} from "../contracts/OFTControls.sol";

interface IOFTCommon {
    function owner() external view returns (address);
    function peers(uint32 eid) external view returns (bytes32);
}

/**
 * @notice Upgrades the live weETH proxies on a fork to the new implementation and checks that
 * (1) every pre-upgrade read is unchanged, (2) send and receive still work through the real endpoint,
 * (3) the new controls work on top of the real state.
 * Runs against the public RPCs in registry/chains.json. Use `forge test --match-path
 * test/OFTControlsUpgradeFork.t.sol --threads 1` to stay under public RPC rate limits.
 */
contract OFTControlsUpgradeForkTest is Test {
    address constant L1_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    uint32 constant ETH_EID = 30101;
    uint256 constant ROLE_HOLDERS_PAUSER = 18;
    uint256 constant ROLE_HOLDERS_UNPAUSER = 19;
    bytes32 constant REVERTED = keccak256("revert");

    struct Target {
        string name;
        address oft;
        address proxyAdmin;
        address endpoint;
        uint32 eid;
        bool adapter;
    }

    address feeDeposit = makeAddr("feeDeposit");
    address escrow = makeAddr("escrow");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address guardian = makeAddr("guardian");
    address blacklister = makeAddr("blacklister");
    address pauser = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address minter = makeAddr("minter");

    // ---------------------------------------------------------------------------------------------
    // one test per live chain
    // ---------------------------------------------------------------------------------------------

    function test_Fork_ethereum() public { _run("ethereum"); }
    function test_Fork_base() public { _run("base"); }
    function test_Fork_op() public { _run("op"); }
    function test_Fork_bnb() public { _run("bnb"); }
    function test_Fork_linea() public { _run("linea"); }
    function test_Fork_unichain() public { _run("unichain"); }
    function test_Fork_avax() public { _run("avax"); }
    function test_Fork_hyperEVM() public { _run("hyperEVM"); }
    function test_Fork_plasma() public { _run("plasma"); }
    function test_Fork_ink() public { _run("ink"); }
    function test_Fork_stable() public { _run("stable"); }
    function test_Fork_monad() public { _run("monad"); }
    function test_Fork_robinhood() public { _run("robinhood"); }
    function test_Fork_arc() public { _run("arc"); }

    // ---------------------------------------------------------------------------------------------
    // flow
    // ---------------------------------------------------------------------------------------------

    function _run(string memory name) internal {
        Target memory c = _load(name);
        vm.createSelectFork(vm.parseJsonString(vm.readFile("registry/chains.json"), string.concat(".", name, ".RPC_URL")));
        // the lane we exercise: L2s talk to Ethereum, the L1 adapter talks to Base
        uint32 peerEid = c.adapter ? 30184 : ETH_EID;
        assertTrue(IOFTCommon(c.oft).peers(peerEid) != bytes32(0), "no peer for test lane");

        bytes32[] memory before = _snapshot(c, peerEid);
        address newImpl = _deployImpl(c);
        _upgrade(c, newImpl);
        bytes32[] memory afterUpgrade = _snapshot(c, peerEid);

        for (uint256 i = 0; i < before.length; i++) {
            bool legacyRoleRead = (i == ROLE_HOLDERS_PAUSER || i == ROLE_HOLDERS_UNPAUSER) && before[i] == REVERTED;
            if (legacyRoleRead && afterUpgrade[i] != before[i]) {
                // OZ AccessControl chains have no roleHolders(). Their holders are re-granted in the upgrade batch.
                emit log_named_string(name, "legacy OZ roles: re-grant holders with setRole in the upgrade batch");
                continue;
            }
            assertEq(afterUpgrade[i], before[i], string.concat(name, ": read changed after upgrade, index ", vm.toString(i)));
        }
        assertEq(address(uint160(uint256(vm.load(c.oft, ERC1967Utils.IMPLEMENTATION_SLOT)))), newImpl);

        _controlsAreOffByDefault(c);
        _existingFlowsStillWork(c, peerEid);
        _controlsWorkOnRealState(c, peerEid);
    }

    function _load(string memory name) internal view returns (Target memory c) {
        string memory json = vm.readFile("registry/chains.json");
        string memory p = string.concat(".", name);
        c.name = name;
        c.oft = vm.parseJsonAddress(json, string.concat(p, ".OFT"));
        c.proxyAdmin = vm.parseJsonAddress(json, string.concat(p, ".PROXY_ADMIN"));
        c.endpoint = vm.parseJsonAddress(json, string.concat(p, ".L2_ENDPOINT"));
        c.eid = uint32(vm.parseJsonUint(json, string.concat(p, ".L2_EID")));
        c.adapter = keccak256(bytes(name)) == keccak256("ethereum");
    }

    function _deployImpl(Target memory c) internal returns (address) {
        if (c.adapter) return address(new EtherfiOFTAdapterUpgradeable(L1_WEETH, c.endpoint));
        return address(new EtherfiOFTUpgradeable(c.endpoint));
    }

    function _upgrade(Target memory c, address newImpl) internal {
        address proxyAdminOwner = ProxyAdmin(c.proxyAdmin).owner();
        vm.prank(proxyAdminOwner);
        ProxyAdmin(c.proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(c.oft),
            newImpl,
            ""
        );
    }

    // ---------------------------------------------------------------------------------------------
    // 1. nothing that existed before changes
    // ---------------------------------------------------------------------------------------------

    function _sendParam(uint32 dstEid, uint256 amount) internal pure returns (SendParam memory) {
        return SendParam(dstEid, bytes32(uint256(uint160(address(0xBEEF)))), amount, 0, "", "", "");
    }

    /// @dev Hash of the return data of each read, or of the revert, so a missing function matches itself.
    function _snapshot(Target memory c, uint32 peerEid) internal view returns (bytes32[] memory out) {
        bytes[] memory calls = new bytes[](20);
        uint256 n;
        calls[n++] = abi.encodeWithSignature("owner()");
        calls[n++] = abi.encodeWithSignature("paused()");
        calls[n++] = abi.encodeWithSignature("decimalConversionRate()");
        calls[n++] = abi.encodeWithSignature("sharedDecimals()");
        calls[n++] = abi.encodeWithSignature("msgInspector()");
        calls[n++] = abi.encodeWithSignature("token()");
        calls[n++] = abi.encodeWithSignature("name()");
        calls[n++] = abi.encodeWithSignature("symbol()");
        calls[n++] = abi.encodeWithSignature("decimals()");
        calls[n++] = abi.encodeWithSignature("totalSupply()");
        calls[n++] = abi.encodeWithSignature("peers(uint32)", peerEid);
        calls[n++] = abi.encodeWithSignature("peers(uint32)", ETH_EID);
        calls[n++] = abi.encodeWithSignature("outboundRateLimits(uint32)", peerEid);
        calls[n++] = abi.encodeWithSignature("inboundRateLimits(uint32)", peerEid);
        calls[n++] = abi.encodeWithSignature("getAmountCanBeSent(uint32)", peerEid);
        calls[n++] = abi.encodeWithSignature("getAmountCanBeReceived(uint32)", peerEid);
        calls[n++] = abi.encodeWithSignature("quoteOFT((uint32,bytes32,uint256,uint256,bytes,bytes,bytes))", _sendParam(peerEid, 1 ether));
        calls[n++] = abi.encodeWithSignature("quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)", _sendParam(peerEid, 1 ether), false);
        calls[n++] = abi.encodeWithSignature("roleHolders(uint256)", 2);
        calls[n++] = abi.encodeWithSignature("roleHolders(uint256)", 3);

        out = new bytes32[](n + 3);
        for (uint256 i = 0; i < n; i++) {
            (bool ok, bytes memory ret) = c.oft.staticcall(calls[i]);
            out[i] = ok ? keccak256(ret) : REVERTED;
        }
        (bool delegateOk, bytes memory delegate) = c.endpoint.staticcall(abi.encodeWithSignature("delegates(address)", c.oft));
        out[n] = delegateOk ? keccak256(delegate) : REVERTED;
        out[n + 1] = vm.load(c.oft, ERC1967Utils.ADMIN_SLOT);
        // rate limit mappings live in slots 0 and 1 and must not move
        out[n + 2] = keccak256(abi.encode(vm.load(c.oft, bytes32(uint256(keccak256(abi.encode(peerEid, uint256(0)))) + 2)), vm.load(c.oft, bytes32(uint256(keccak256(abi.encode(peerEid, uint256(1)))) + 2))));
    }

    function _controlsAreOffByDefault(Target memory c) internal view {
        OFTControls oft = OFTControls(c.oft);
        assertEq(uint8(oft.allowlistMode()), uint8(IAllowlist.AllowlistMode.Open), "allowlist not open");
        assertEq(oft.defaultFeeBps(), 0, "fee not zero");
        assertEq(oft.feeDeposit(), address(0), "fee deposit");
        assertEq(oft.escrow(), address(0), "escrow");
        assertEq(oft.pausedUntil(), 0, "pausedUntil");
        assertEq(oft.pauseUntilDuration(), 0, "duration");
    }

    // ---------------------------------------------------------------------------------------------
    // 2. send and receive through the real endpoint
    // ---------------------------------------------------------------------------------------------

    function _fund(Target memory c, address to, uint256 amount) internal {
        if (c.adapter) {
            // the lockbox holds the L1 weETH, borrow from it
            vm.prank(c.oft);
            IERC20(L1_WEETH).transfer(to, amount);
        } else {
            vm.prank(IOFTCommon(c.oft).owner());
            EtherfiOFTUpgradeable(c.oft).setRole(minter, 1, true);
            vm.prank(minter);
            EtherfiOFTUpgradeable(c.oft).mint(to, amount);
        }
    }

    function _balance(Target memory c, address who) internal view returns (uint256) {
        return IERC20(c.adapter ? L1_WEETH : c.oft).balanceOf(who);
    }

    function _send(Target memory c, address from, uint32 dstEid, uint256 amount) internal returns (OFTReceipt memory receipt) {
        SendParam memory param = SendParam(dstEid, bytes32(uint256(uint160(from))), amount, 0, "", "", "");
        MessagingFee memory fee = EtherfiOFTUpgradeable(c.oft).quoteSend(param, false);
        vm.deal(from, fee.nativeFee + 1 ether);
        if (c.adapter) {
            vm.prank(from);
            IERC20(L1_WEETH).approve(c.oft, amount);
        }
        vm.prank(from);
        (, receipt) = EtherfiOFTUpgradeable(c.oft).send{value: fee.nativeFee}(param, fee, from);
    }

    function _receive(Target memory c, uint32 srcEid, address to, uint256 amountLD) internal {
        Origin memory origin = Origin(srcEid, IOFTCommon(c.oft).peers(srcEid), 1);
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(to))), uint64(amountLD / 1e12));
        vm.prank(c.endpoint);
        EtherfiOFTUpgradeable(c.oft).lzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function _existingFlowsStillWork(Target memory c, uint32 peerEid) internal {
        _fund(c, user, 10 ether);
        uint256 userBefore = _balance(c, user);

        OFTReceipt memory receipt = _send(c, user, peerEid, 1 ether);
        assertEq(receipt.amountSentLD, 1 ether, "sent");
        assertEq(receipt.amountReceivedLD, 1 ether, "received");
        assertEq(_balance(c, user), userBefore - 1 ether, "sender balance");

        uint256 user2Before = _balance(c, user2);
        _receive(c, peerEid, user2, 2 ether);
        assertEq(_balance(c, user2), user2Before + 2 ether, "recipient balance");
    }

    // ---------------------------------------------------------------------------------------------
    // 3. the new controls on top of the real state
    // ---------------------------------------------------------------------------------------------

    function _grant(Target memory c, address who, uint256 l2RoleId, bytes32 adapterRole) internal {
        vm.prank(IOFTCommon(c.oft).owner());
        if (c.adapter) EtherfiOFTAdapterUpgradeable(c.oft).grantRole(adapterRole, who);
        else EtherfiOFTUpgradeable(c.oft).setRole(who, l2RoleId, true);
    }

    function _controlsWorkOnRealState(Target memory c, uint32 peerEid) internal {
        // roles: the legacy chains start with empty roles after the upgrade, so grant what each check needs
        _grant(c, guardian, 6, keccak256("PAUSER_UNTIL_ROLE"));
        _grant(c, blacklister, 4, keccak256("BLACKLISTER_ROLE"));
        vm.startPrank(IOFTCommon(c.oft).owner());
        OFTControls(c.oft).setFeeDeposit(feeDeposit);
        OFTControls(c.oft).setPauseUntilDuration(1 days);
        vm.stopPrank();
        _grant(c, pauser, 2, keccak256("PAUSER_ROLE"));
        _grant(c, unpauser, 3, keccak256("UNPAUSER_ROLE"));

        _feeWorks(c, peerEid);
        _blacklistWorks(c, peerEid);
        _pausesWork(c, peerEid);
    }

    /// @dev The destination receives the post-fee amount and the fee deposit gets the difference.
    function _feeWorks(Target memory c, uint32 peerEid) internal {
        OFTControls oft = OFTControls(c.oft);
        address owner = IOFTCommon(c.oft).owner();
        vm.prank(owner);
        oft.setDefaultFeeBps(50);
        uint256 depositBefore = _balance(c, feeDeposit);
        OFTReceipt memory receipt = _send(c, user, peerEid, 1 ether);
        assertEq(receipt.amountReceivedLD, 0.995 ether, "post-fee amount");
        assertEq(_balance(c, feeDeposit) - depositBefore, 0.005 ether, "fee paid");
        vm.prank(owner);
        oft.setDefaultFeeBps(0);
    }

    /// @dev A blocked recipient is redirected to escrow, a blocked holder cannot bridge out, and the
    /// owner can recover from a blocked holder on the L2 token.
    function _blacklistWorks(Target memory c, uint32 peerEid) internal {
        OFTControls oft = OFTControls(c.oft);
        address owner = IOFTCommon(c.oft).owner();

        _fund(c, user2, 3 ether);
        vm.startPrank(owner);
        oft.setEscrow(escrow);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Blacklist);
        vm.stopPrank();
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam(user2, true);
        vm.prank(blacklister);
        oft.setBlacklisted(params);

        uint256 escrowBefore = _balance(c, escrow);
        uint256 user2Before = _balance(c, user2);
        _receive(c, peerEid, user2, 1 ether);
        assertEq(_balance(c, escrow) - escrowBefore, 1 ether, "redirected to escrow");
        assertEq(_balance(c, user2), user2Before, "blocked recipient got nothing");

        _expectSendReverts(c, user2, peerEid);

        if (!c.adapter) {
            vm.prank(owner);
            EtherfiOFTUpgradeable(c.oft).recoverFunds(user2, escrow, user2Before);
            assertEq(_balance(c, user2), 0, "recovered");
        }

        // back to open: the same holder can bridge again, so the revert above came from the blacklist
        vm.prank(owner);
        oft.setAllowlistMode(IAllowlist.AllowlistMode.Open);
        if (c.adapter) _send(c, user2, peerEid, 0.1 ether);
    }

    /// @dev The guardian pause stops the bridge and expires by itself. A lane pause stops one lane.
    function _pausesWork(Target memory c, uint32 peerEid) internal {
        OFTControls oft = OFTControls(c.oft);

        vm.prank(guardian);
        oft.pauseBridgeUntil();
        uint256 until = oft.pausedUntil();
        _expectSendReverts(c, user, peerEid);
        vm.warp(until + 1);
        _send(c, user, peerEid, 0.1 ether);

        vm.prank(pauser);
        oft.setLanePaused(peerEid, true);
        _expectSendReverts(c, user, peerEid);
        vm.prank(unpauser);
        oft.setLanePaused(peerEid, false);
        _send(c, user, peerEid, 0.1 ether);
    }

    function _expectSendReverts(Target memory c, address from, uint32 dstEid) internal {
        SendParam memory param = SendParam(dstEid, bytes32(uint256(uint160(from))), 0.1 ether, 0, "", "", "");
        MessagingFee memory fee = EtherfiOFTUpgradeable(c.oft).quoteSend(param, false);
        vm.deal(from, fee.nativeFee + 1 ether);
        if (c.adapter) {
            vm.prank(from);
            IERC20(L1_WEETH).approve(c.oft, 0.1 ether);
        }
        vm.prank(from);
        (bool ok, ) = c.oft.call{value: fee.nativeFee}(
            abi.encodeWithSignature("send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)", param, fee, from)
        );
        assertFalse(ok, "send should revert");
    }
}
