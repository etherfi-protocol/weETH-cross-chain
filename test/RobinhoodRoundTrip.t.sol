// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { ILayerZeroEndpointV2, MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";

import "../contracts/EtherfiOFTUpgradeable.sol";
import "../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../contracts/PairwiseRateLimiter.sol";
import "../utils/LayerZeroHelpers.sol";

import "forge-std/Test.sol";

interface IEndpointDelegates {
    function delegates(address oapp) external view returns (address);
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

/**
 * @title RobinhoodRoundTrip
 * @notice Forks every chain in the Robinhood weETH OFT mesh and proves the bridge works
 *         BOTH WAYS once the #574 reverse-wiring config is applied:
 *           - outbound  chain -> Robinhood  (exercises that chain's OUTBOUND rate limit via _debit)
 *           - inbound   Robinhood -> chain  (exercises that chain's INBOUND rate limit via _credit)
 *         and that an unset rate limit reverts (the bug this guards against).
 *
 *   ROBINHOOD_MAINNET_RPC_URL=... TARGET_CHAIN=robinhood \
 *   forge test --match-contract RobinhoodRoundTrip -vv
 */
contract RobinhoodRoundTrip is Test {
    // -------- Robinhood (the new chain) --------
    uint32  constant RH_EID      = 30416;
    address constant RH_OFT      = 0xA3D68b74bF0528fdD07263c60d6488749044914b;
    address constant RH_ENDPOINT = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant RH_SEND_302 = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    address constant RH_RECV_302 = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;

    // Canonical Robinhood-pathway rate limit (registry: peerLimits/peerWindows).
    uint256 constant RL_LIMIT  = 1000 ether;
    uint256 constant RL_WINDOW = 14400;

    bytes constant ENFORCED_OPT = hex"00030100110100000000000000000000000000029810"; // 170k lzReceive

    struct ChainCfg {
        string  name;
        string  rpc;
        uint32  eid;
        address oft;        // OFT (L2) or adapter (L1)
        address endpoint;
        address send302;
        address recv302;
        address weeth;      // token pulled on send (L1: separate weETH; L2: the OFT itself)
        bool    isAdapter;  // L1 lock/unlock adapter
        address[4] dvns;    // sorted ascending
    }

    function _eth() internal view returns (ChainCfg memory c) {
        c.name = "ethereum";
        c.rpc = vm.envOr("ETH_MAINNET_RPC_URL", string("https://mainnet.gateway.tenderly.co"));
        c.eid = 30101;
        c.oft = 0xcd2eb13D6831d4602D80E5db9230A57596CDCA63;
        c.endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
        c.send302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
        c.recv302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
        c.weeth = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        c.isAdapter = true;
        c.dvns = [
            0x380275805876Ff19055EA900CDb2B46a94ecF20D,
            0x589dEDbD617e0CBcB916A9223F4d1300c294236b,
            0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd,
            0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5
        ];
    }

    function _base() internal view returns (ChainCfg memory c) {
        c.name = "base";
        c.rpc = vm.envOr("BASE_MAINNET_RPC_URL", string("https://mainnet.base.org"));
        c.eid = 30184;
        c.oft = 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A;
        c.endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
        c.send302 = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
        c.recv302 = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;
        c.weeth = 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A;
        c.isAdapter = false;
        c.dvns = [
            0x554833698Ae0FB22ECC90B01222903fD62CA4B47,
            0x9e059a54699a285714207b43B055483E78FAac25,
            0xa7b5189bcA84Cd304D8553977c7C614329750d99,
            0xcd37CA043f8479064e10635020c65FfC005d36f6
        ];
    }

    function _op() internal view returns (ChainCfg memory c) {
        c.name = "optimism";
        c.rpc = vm.envOr("OP_MAINNET_RPC_URL", string("https://optimism-rpc.publicnode.com"));
        c.eid = 30111;
        c.oft = 0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF;
        c.endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
        c.send302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
        c.recv302 = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;
        c.weeth = 0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF;
        c.isAdapter = false;
        c.dvns = [
            0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f,
            0x6A02D83e8d433304bba74EF1c427913958187142,
            0x9E930731cb4A6bf7eCc11F695A295c60bDd212eB,
            0xa7b5189bcA84Cd304D8553977c7C614329750d99
        ];
    }

    // ------------------------------------------------------------------
    // Tests: each existing chain <-> Robinhood, both directions
    // ------------------------------------------------------------------

    function testEthereumRoundTrip() public { _roundTrip(_eth()); }
    function testBaseRoundTrip() public { _roundTrip(_base()); }
    function testOptimismRoundTrip() public { _roundTrip(_op()); }

    // Proves the bug: same config minus the rate-limit calls -> both directions revert.
    function testEthereumRevertsWithoutRateLimits() public { _provesBug(_eth()); }
    function testBaseRevertsWithoutRateLimits() public { _provesBug(_base()); }
    function testOptimismRevertsWithoutRateLimits() public { _provesBug(_op()); }

    // Robinhood side ("fro"): config already live from deployment; bridge to/from every peer.
    function testRobinhoodToAndFroAllPeers() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"));
        // Robinhood's live rate limits were checkpointed at config time; ensure the fork clock is
        // past that so the linear-decay math (block.timestamp - lastUpdated) never underflows.
        if (block.timestamp < 1790000000) vm.warp(1790000000);
        ChainCfg[3] memory peers = [_eth(), _base(), _op()];
        for (uint256 i = 0; i < peers.length; i++) {
            console.log("Robinhood <-> %s (eid %d)", peers[i].name, peers[i].eid);
            // Inbound first: forge deal() on the OFT's ERC-7201 storage perturbs totalSupply, so
            // exercising the mint path before any deal() keeps the credit accounting honest.
            // inbound peer -> Robinhood (recipient is minted weETH = the OFT itself)
            _deliver(RH_OFT, RH_OFT, RH_ENDPOINT, peers[i].eid, peers[i].oft, 1 ether, false);
            // outbound Robinhood -> peer
            _send(RH_OFT, RH_OFT, peers[i].eid, 1 ether, false);
            console.log("   ok: Robinhood->%s send + %s->Robinhood receive", peers[i].name, peers[i].name);
        }
    }

    // ------------------------------------------------------------------
    // END-TO-END: replay the EXACT proposed 3CP Safe transactions (schedule -> warp past the
    // timelock delay -> execute, or direct Safe calls), THEN bridge on the same post-execution
    // fork. This proves the literal bytes signers approve make every configured pathway work.
    //
    // Point PROPOSAL_DIR at the queued/<N> folder (per-chain subfolders):
    //   PROPOSAL_DIR=/abs/path/3CP-secure/queued/574 \
    //   ETH_MAINNET_RPC_URL=… BASE_MAINNET_RPC_URL=… OP_MAINNET_RPC_URL=… \
    //   forge test --match-test testProposalEndToEnd -vv
    // ------------------------------------------------------------------

    uint256 constant TIMELOCK_DELAY = 172800; // L1 operating timelock minDelay (2 days)

    function testProposalEndToEnd_AllChains() public {
        string memory dir = vm.envOr("PROPOSAL_DIR", string(""));
        if (bytes(dir).length == 0) {
            console.log("SKIP testProposalEndToEnd: set PROPOSAL_DIR to the queued/<N> folder");
            return;
        }

        // Base — direct Safe call (OFT owned by the controller Safe).
        ChainCfg memory b = _base();
        vm.createSelectFork(b.rpc);
        _applyDirectProposal(string.concat(dir, "/base/base.json"));
        _assertBridges(b, "base");

        // Optimism — direct Safe call.
        ChainCfg memory o = _op();
        vm.createSelectFork(o.rpc);
        _applyDirectProposal(string.concat(dir, "/optimism/optimism.json"));
        _assertBridges(o, "optimism");

        // Ethereum — timelock: scheduleBatch -> warp past delay -> executeBatch.
        ChainCfg memory e = _eth();
        vm.createSelectFork(e.rpc);
        _applyTimelockProposal(
            string.concat(dir, "/ethereum/ethereum-schedule.json"),
            string.concat(dir, "/ethereum/ethereum-execute.json")
        );
        _assertBridges(e, "ethereum");
    }

    // Replay every transaction in a Safe-tx-builder JSON, sent by its declared safeAddress.
    function _applyProposalFile(string memory path) internal {
        string memory json = vm.readFile(path);
        address safe = vm.parseJsonAddress(json, ".safeAddress");
        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "].to"))) {
            address to = vm.parseJsonAddress(json, string.concat(".transactions[", vm.toString(i), "].to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(".transactions[", vm.toString(i), "].data"));
            vm.prank(safe);
            (bool ok, bytes memory ret) = to.call(data);
            if (!ok) {
                console.log("proposal tx %d reverted in %s", i, path);
                assembly { revert(add(ret, 0x20), mload(ret)) }
            }
            i++;
        }
        console.log("   applied %d proposal txns (safe %s)", i, safe);
    }

    function _applyDirectProposal(string memory path) internal {
        _applyProposalFile(path);
    }

    function _applyTimelockProposal(string memory schedulePath, string memory executePath) internal {
        _applyProposalFile(schedulePath);          // Safe -> timelock.scheduleBatch
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        _applyProposalFile(executePath);           // Safe -> timelock.executeBatch (after delay)
    }

    // After the real proposal executed on this fork: limits are non-zero and the bridge works both ways.
    function _assertBridges(ChainCfg memory c, string memory label) internal {
        (,, uint256 inLim,) = PairwiseRateLimiter(c.oft).inboundRateLimits(RH_EID);
        (,, uint256 outLim,) = PairwiseRateLimiter(c.oft).outboundRateLimits(RH_EID);
        assertGt(inLim, 0, "inbound limit unset after proposal");
        assertGt(outLim, 0, "outbound limit unset after proposal");

        _send(c.oft, c.weeth, RH_EID, 1 ether, false);
        _send(c.oft, c.weeth, RH_EID, inLim + 1 ether, true);
        _deliver(c.oft, c.weeth, c.endpoint, RH_EID, RH_OFT, 1 ether, false);
        _deliver(c.oft, c.weeth, c.endpoint, RH_EID, RH_OFT, inLim + 1 ether, true);
        console.log("   ok (post-proposal): %s <-> Robinhood both ways; over-limit reverts", label);
    }

    // ------------------------------------------------------------------
    // Core round-trip on an existing chain's fork
    // ------------------------------------------------------------------

    function _roundTrip(ChainCfg memory c) internal {
        vm.createSelectFork(c.rpc);
        _applyReverseWiring(c, true);
        console.log("== %s <-> Robinhood (with rate limits) ==", c.name);

        // sanity: limits are non-zero both ways
        (,, uint256 inLim,) = PairwiseRateLimiter(c.oft).inboundRateLimits(RH_EID);
        (,, uint256 outLim,) = PairwiseRateLimiter(c.oft).outboundRateLimits(RH_EID);
        assertEq(inLim, RL_LIMIT, "inbound limit");
        assertEq(outLim, RL_LIMIT, "outbound limit");

        // outbound chain -> Robinhood: 1 weETH ok, over-limit reverts
        _send(c.oft, c.weeth, RH_EID, 1 ether, false);
        _send(c.oft, c.weeth, RH_EID, RL_LIMIT + 1 ether, true);
        console.log("   ok: %s -> Robinhood send (1 weETH); over-limit reverts", c.name);

        // inbound Robinhood -> chain: 1 weETH ok, over-limit reverts
        _deliver(c.oft, c.weeth, c.endpoint, RH_EID, RH_OFT, 1 ether, false);
        _deliver(c.oft, c.weeth, c.endpoint, RH_EID, RH_OFT, RL_LIMIT + 1 ether, true);
        console.log("   ok: Robinhood -> %s receive (1 weETH); over-limit reverts", c.name);
    }

    function _provesBug(ChainCfg memory c) internal {
        vm.createSelectFork(c.rpc);
        _applyReverseWiring(c, false); // NO rate limits -> pathway stays at limit 0
        console.log("== %s <-> Robinhood (NO rate limits - expect reverts) ==", c.name);
        _send(c.oft, c.weeth, RH_EID, 1 ether, true);                    // OutboundRateLimitExceeded
        _deliver(c.oft, c.weeth, c.endpoint, RH_EID, RH_OFT, 1 ether, true); // InboundRateLimitExceeded
        console.log("   confirmed: both directions revert without rate-limit config");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _applyReverseWiring(ChainCfg memory c, bool withRateLimits) internal {
        // Precompute everything that touches a public library (delegatecall) BEFORE pranking —
        // a delegatecall between vm.prank and the target call would consume the prank.
        address owner = EtherfiOFTUpgradeable(c.oft).owner();
        address delegate = IEndpointDelegates(c.endpoint).delegates(c.oft);
        bytes32 peerB32 = LayerZeroHelpers._toBytes32(RH_OFT);
        bytes memory uln = LayerZeroHelpers._getExpectedUln4(c.dvns);

        PairwiseRateLimiter.RateLimitConfig[] memory rl = new PairwiseRateLimiter.RateLimitConfig[](1);
        rl[0] = PairwiseRateLimiter.RateLimitConfig({ peerEid: RH_EID, limit: RL_LIMIT, window: RL_WINDOW });

        EnforcedOptionParam[] memory eo = new EnforcedOptionParam[](2);
        eo[0] = EnforcedOptionParam({ eid: RH_EID, msgType: 1, options: ENFORCED_OPT });
        eo[1] = EnforcedOptionParam({ eid: RH_EID, msgType: 2, options: ENFORCED_OPT });

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({ eid: RH_EID, configType: 2, config: uln });

        vm.startPrank(owner);
        EtherfiOFTUpgradeable(c.oft).setPeer(RH_EID, peerB32);
        if (withRateLimits) {
            EtherfiOFTUpgradeable(c.oft).setInboundRateLimits(rl);
            EtherfiOFTUpgradeable(c.oft).setOutboundRateLimits(rl);
        }
        EtherfiOFTUpgradeable(c.oft).setEnforcedOptions(eo);
        vm.stopPrank();

        // 4-of-4 DVN ULN on send + receive libs (delegate-gated)
        vm.startPrank(delegate);
        ILayerZeroEndpointV2(c.endpoint).setConfig(c.oft, c.send302, params);
        ILayerZeroEndpointV2(c.endpoint).setConfig(c.oft, c.recv302, params);
        vm.stopPrank();
    }

    // Outbound: real send through LayerZero. expectRevert => must revert (rate limit).
    function _send(address oft, address weeth, uint32 dstEid, uint256 amount, bool expectRevert) internal {
        address sender = vm.addr(0x5e7d);
        vm.deal(sender, 10 ether);
        deal(weeth, sender, amount);
        vm.prank(sender);
        IERC20(weeth).approve(oft, amount);

        SendParam memory p = SendParam({
            dstEid: dstEid,
            to: LayerZeroHelpers._toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        if (expectRevert) {
            vm.prank(sender);
            // fee quote may itself revert post-debit; wrap the whole call
            try IOFT(oft).quoteSend(p, false) returns (MessagingFee memory fee) {
                vm.prank(sender);
                vm.expectRevert();
                IOFT(oft).send{value: fee.nativeFee}(p, fee, sender);
            } catch {
                // quoteSend reverted -> pathway unusable, also acceptable proof
            }
            return;
        }

        MessagingFee memory fee2 = IOFT(oft).quoteSend(p, false);
        vm.prank(sender);
        IOFT(oft).send{value: fee2.nativeFee}(p, fee2, sender);
    }

    // Inbound: impersonate the endpoint and deliver an OFT message from `srcOft` on `srcEid`.
    function _deliver(address oft, address weeth, address endpoint, uint32 srcEid, address srcOft, uint256 amount, bool expectRevert) internal {
        address recipient = vm.addr(0xbabe);
        uint256 before = IERC20(weeth).balanceOf(recipient);
        uint64 amountSD = uint64(amount / 1e12); // 18 local - 6 shared decimals
        bytes memory message = abi.encodePacked(LayerZeroHelpers._toBytes32(recipient), amountSD);
        Origin memory origin = Origin({ srcEid: srcEid, sender: LayerZeroHelpers._toBytes32(srcOft), nonce: 1 });

        if (expectRevert) vm.expectRevert();
        vm.prank(endpoint);
        ILzReceiver(oft).lzReceive(origin, keccak256("rt-guid"), message, address(0), "");

        if (!expectRevert) {
            assertGt(IERC20(weeth).balanceOf(recipient), before, "recipient not credited");
        }
    }
}
