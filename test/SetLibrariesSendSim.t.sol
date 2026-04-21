// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, OFTReceipt, MessagingReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IMessageLibManager} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../utils/LayerZeroHelpers.sol";

interface IOFT_Send {
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory, OFTReceipt memory);

    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUlnBase {
    function getAppUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory);
}

contract SetLibrariesSendSimTest is Test, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;

    uint256 constant SEND_AMOUNT = 1 ether;
    uint128 constant GAS_LIMIT = 200_000;

    uint32[] allL2Eids;

    function setUp() public {
        allL2Eids.push(BLAST.L2_EID);
        allL2Eids.push(MODE.L2_EID);
        allL2Eids.push(MORPH.L2_EID);
        allL2Eids.push(ZKSYNC.L2_EID);
        allL2Eids.push(SONIC.L2_EID);
        allL2Eids.push(SCROLL.L2_EID);
        allL2Eids.push(STABLE.L2_EID);
        allL2Eids.push(AVAX.L2_EID);
        allL2Eids.push(SWELL.L2_EID);
        allL2Eids.push(BNB.L2_EID);
        allL2Eids.push(BERA.L2_EID);
        allL2Eids.push(LINEA.L2_EID);
        allL2Eids.push(UNICHAIN.L2_EID);
        allL2Eids.push(HYPEREVM.L2_EID);
        allL2Eids.push(PLASMA.L2_EID);
        allL2Eids.push(INK.L2_EID);
        allL2Eids.push(MONAD.L2_EID);
        allL2Eids.push(BASE.L2_EID);
        allL2Eids.push(OP.L2_EID);
    }

    function _buildSendParam(uint32 dstEid, address sender) internal pure returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);
        return SendParam({
            dstEid: dstEid,
            to: LayerZeroHelpers._toBytes32(sender),
            amountLD: SEND_AMOUNT,
            minAmountLD: SEND_AMOUNT,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
    }

    function _simulateSend(
        IOFT_Send oft,
        uint32 dstEid,
        address sender,
        string memory label
    ) internal {
        SendParam memory sendParam = _buildSendParam(dstEid, sender);
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        console.log(string.concat("  [", label, "] quoteSend fee (wei):"), fee.nativeFee);

        vm.deal(sender, fee.nativeFee + 1 ether);
        vm.prank(sender);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
            oft.send{value: fee.nativeFee}(sendParam, fee, sender);

        console.log(string.concat("  [", label, "] amountSentLD:"), oftReceipt.amountSentLD);
        console.logBytes32(receipt.guid);

        assertGt(oftReceipt.amountSentLD, 0, string.concat(label, ": amountSentLD should be > 0"));
    }

    function _assertLibrariesPinned(
        address endpoint,
        address oapp,
        uint32[] memory peerEids,
        address expectedSendLib,
        address expectedRecvLib,
        string memory chainName
    ) internal view {
        IMessageLibManager mgr = IMessageLibManager(endpoint);
        for (uint256 i = 0; i < peerEids.length; i++) {
            assertFalse(
                mgr.isDefaultSendLibrary(oapp, peerEids[i]),
                string.concat(chainName, ": send lib should not be default for eid ", vm.toString(peerEids[i]))
            );
            address sendLib = mgr.getSendLibrary(oapp, peerEids[i]);
            assertEq(sendLib, expectedSendLib, string.concat(chainName, ": wrong send lib for eid ", vm.toString(peerEids[i])));

            (address recvLib, bool isDefault) = mgr.getReceiveLibrary(oapp, peerEids[i]);
            assertFalse(isDefault, string.concat(chainName, ": recv lib should not be default for eid ", vm.toString(peerEids[i])));
            assertEq(recvLib, expectedRecvLib, string.concat(chainName, ": wrong recv lib for eid ", vm.toString(peerEids[i])));
        }
        console.log(string.concat("  ", chainName, ": all libraries pinned (", vm.toString(peerEids.length), " peers)"));
    }

    function _assertDvnsPinned(
        address sendLib,
        address recvLib,
        address oapp,
        uint32[] memory peerEids,
        string memory chainName
    ) internal view {
        for (uint256 i = 0; i < peerEids.length; i++) {
            UlnConfig memory sendCfg = IUlnBase(sendLib).getAppUlnConfig(oapp, peerEids[i]);
            assertGt(
                sendCfg.requiredDVNCount, 0,
                string.concat(chainName, ": send DVN not pinned for eid ", vm.toString(peerEids[i]))
            );

            UlnConfig memory recvCfg = IUlnBase(recvLib).getAppUlnConfig(oapp, peerEids[i]);
            assertGt(
                recvCfg.requiredDVNCount, 0,
                string.concat(chainName, ": recv DVN not pinned for eid ", vm.toString(peerEids[i]))
            );
        }
        console.log(string.concat("  ", chainName, ": all DVNs pinned (", vm.toString(peerEids.length), " peers, send+recv)"));
    }

    function _peerEidsFor(uint32 selfEid) internal view returns (uint32[] memory) {
        uint32[] memory peers = new uint32[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            peers[i] = allL2Eids[i] == selfEid ? L1_EID : allL2Eids[i];
        }
        return peers;
    }

    // ================================================================
    //                    Helper: L2 set-libraries + verify + send
    // ================================================================

    function _testL2SetLibraries(ConfigPerL2 storage chain) internal {
        vm.createSelectFork(chain.RPC_URL);
        console.log(string.concat("=== ", chain.NAME, " FORK (chainId: ", chain.CHAIN_ID, ") ==="));

        string memory path = string.concat("./output/", chain.NAME, "-SetLibraries.json");
        executeGnosisTransactionBundle(path, chain.L2_CONTRACT_CONTROLLER_SAFE);
        console.log("  SetLibraries batch executed");

        uint32[] memory peers = _peerEidsFor(chain.L2_EID);
        _assertLibrariesPinned(
            chain.L2_ENDPOINT, chain.L2_OFT, peers,
            chain.SEND_302, chain.RECEIVE_302, chain.NAME
        );

        _assertDvnsPinned(
            chain.SEND_302, chain.RECEIVE_302, chain.L2_OFT,
            peers, chain.NAME
        );

        address sender = address(0xBEEF);
        deal(chain.L2_OFT, sender, 5 ether);

        _simulateSend(IOFT_Send(chain.L2_OFT), L1_EID, sender, string.concat(chain.NAME, "->ETH"));
        console.log(string.concat("  ", chain.NAME, " send succeeded"));
    }

    // ================================================================
    //                    Single test: all chains
    // ================================================================

    function testAllChainsSetLibraries() public {
        // --- Ethereum ---
        vm.createSelectFork(L1_RPC_URL);
        console.log("=== ETHEREUM FORK (chainId: 1) ===");

        executeGnosisTransactionBundle("./output/ethereum-SetLibraries.json", L1_CONTRACT_CONTROLLER);
        console.log("  SetLibraries batch executed on Ethereum");

        uint32[] memory ethPeers = new uint32[](allL2Eids.length);
        for (uint256 i = 0; i < allL2Eids.length; i++) {
            ethPeers[i] = allL2Eids[i];
        }
        _assertLibrariesPinned(L1_ENDPOINT, L1_OFT_ADAPTER, ethPeers, L1_SEND_302, L1_RECEIVE_302, "ethereum");
        _assertDvnsPinned(L1_SEND_302, L1_RECEIVE_302, L1_OFT_ADAPTER, ethPeers, "ethereum");

        address sender = address(0xBEEF);
        vm.deal(sender, 100 ether);
        address weethWhale = 0x267ed5f71EE47D3E45Bb1569Aa37889a2d10f91e;
        vm.prank(weethWhale);
        IERC20(L1_WEETH).transfer(sender, 5 ether);
        vm.prank(sender);
        IERC20(L1_WEETH).approve(L1_OFT_ADAPTER, type(uint256).max);
        _simulateSend(IOFT_Send(L1_OFT_ADAPTER), BASE.L2_EID, sender, "ETH->Base");
        console.log("  Ethereum send succeeded\n");

        // --- All L2s (except zkSync) ---
        _testL2SetLibraries(BASE);
        _testL2SetLibraries(OP);
        _testL2SetLibraries(UNICHAIN);
        _testL2SetLibraries(LINEA);
        _testL2SetLibraries(BERA);
        // AVAX public RPC is not an archive node — skip alongside zkSync
        _testL2SetLibraries(BNB);
        _testL2SetLibraries(SONIC);
        _testL2SetLibraries(HYPEREVM);
        _testL2SetLibraries(SCROLL);
        _testL2SetLibraries(BLAST);
        _testL2SetLibraries(MODE);
        _testL2SetLibraries(MORPH);
        _testL2SetLibraries(SWELL);
        _testL2SetLibraries(MONAD);
        _testL2SetLibraries(PLASMA);
        _testL2SetLibraries(INK);
        _testL2SetLibraries(STABLE);

        console.log("\n=== ALL 18 CHAINS PASSED (zkSync + AVAX excluded due to RPC limits) ===");
    }
}
