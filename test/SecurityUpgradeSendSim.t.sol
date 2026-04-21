// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, OFTReceipt, MessagingReceipt, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

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
    function paused() external view returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract SecurityUpgradeSendSimTest is Test, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;

    uint256 constant SEND_AMOUNT = 1 ether;
    uint128 constant GAS_LIMIT = 200_000;

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
        console.log(string.concat("  [", label, "] amountReceivedLD:"), oftReceipt.amountReceivedLD);
        console.log(string.concat("  [", label, "] guid:"));
        console.logBytes32(receipt.guid);

        assertGt(oftReceipt.amountSentLD, 0, string.concat(label, ": amountSentLD should be > 0"));
    }

    // ================================================================
    //                    Helper: simulate regular L2 upgrade
    // ================================================================

    function _testRegularL2Upgrade(ConfigPerL2 storage chain) internal {
        vm.createSelectFork(chain.RPC_URL);
        console.log(string.concat("=== ", chain.NAME, " FORK (chainId: ", chain.CHAIN_ID, ") ==="));

        string memory path = string.concat("./output/", chain.NAME, "-SecurityUpgrade.json");
        executeGnosisTransactionBundle(path, chain.L2_CONTRACT_CONTROLLER_SAFE);
        console.log("  Gnosis batch executed");

        assertFalse(IOFT_Send(chain.L2_OFT).paused(), "Bridge should be unpaused");
        console.log("  Bridge unpaused: true");

        address sender = address(0xBEEF);
        deal(chain.L2_OFT, sender, 5 ether);

        console.log(string.concat("  --- Send 1 weETH: ", chain.NAME, " -> Ethereum ---"));
        _simulateSend(IOFT_Send(chain.L2_OFT), L1_EID, sender, string.concat(chain.NAME, "->ETH"));
        console.log(string.concat("  All ", chain.NAME, " sends succeeded"));
    }

    // ================================================================
    //                    Helper: simulate timelocked L2 upgrade
    // ================================================================

    function _testTimelockL2Upgrade(ConfigPerL2 storage chain) internal {
        vm.createSelectFork(chain.RPC_URL);
        console.log(string.concat("=== ", chain.NAME, " FORK [TIMELOCK] (chainId: ", chain.CHAIN_ID, ") ==="));

        address safe = chain.L2_CONTRACT_CONTROLLER_SAFE;

        executeGnosisTransactionBundle(string.concat("./output/", chain.NAME, "-SecurityUpgrade.json"), safe);
        console.log("  SecurityUpgrade (unpause + DVN) executed");

        executeGnosisTransactionBundle(string.concat("./output/", chain.NAME, "-TimelockSchedule.json"), safe);
        console.log("  TimelockSchedule executed");

        vm.warp(block.timestamp + 3 days);

        executeGnosisTransactionBundle(string.concat("./output/", chain.NAME, "-TimelockExecute.json"), safe);
        console.log("  TimelockExecute executed (after 3-day warp)");

        assertFalse(IOFT_Send(chain.L2_OFT).paused(), "Bridge should be unpaused");
        console.log("  Bridge unpaused: true");

        address sender = address(0xBEEF);
        deal(chain.L2_OFT, sender, 5 ether);

        console.log(string.concat("  --- Send 1 weETH: ", chain.NAME, " -> Ethereum ---"));
        _simulateSend(IOFT_Send(chain.L2_OFT), L1_EID, sender, string.concat(chain.NAME, "->ETH"));
        console.log(string.concat("  All ", chain.NAME, " sends succeeded"));
    }

    // ================================================================
    //                    Ethereum
    // ================================================================

    function testEthereumSendAfterUpgrade() public {
        vm.createSelectFork(L1_RPC_URL);
        console.log("=== ETHEREUM FORK (chainId: 1) ===");

        executeGnosisTransactionBundle("./output/ethereum-SecurityUpgrade.json", L1_CONTRACT_CONTROLLER);
        console.log("  Gnosis batch executed on Ethereum");

        IOFT_Send adapter = IOFT_Send(L1_OFT_ADAPTER);
        assertFalse(adapter.paused(), "Bridge should be unpaused");

        address sender = address(0xBEEF);
        vm.deal(sender, 100 ether);

        address weethWhale = 0x267ed5f71EE47D3E45Bb1569Aa37889a2d10f91e;
        vm.prank(weethWhale);
        IERC20(L1_WEETH).transfer(sender, 5 ether);

        vm.prank(sender);
        IERC20(L1_WEETH).approve(L1_OFT_ADAPTER, type(uint256).max);

        _simulateSend(adapter, BASE.L2_EID, sender, "ETH->Base");
        _simulateSend(adapter, OP.L2_EID, sender, "ETH->OP");
    }

    // ================================================================
    //                    Regular L2 chains
    // ================================================================

    function testBaseAfterUpgrade() public { _testRegularL2Upgrade(BASE); }
    function testOPAfterUpgrade() public { _testRegularL2Upgrade(OP); }
    function testUnichainAfterUpgrade() public { _testRegularL2Upgrade(UNICHAIN); }
    function testLineaAfterUpgrade() public { _testRegularL2Upgrade(LINEA); }
    function testBeraAfterUpgrade() public { _testRegularL2Upgrade(BERA); }
    function testAvaxAfterUpgrade() public { _testRegularL2Upgrade(AVAX); }
    function testBnbAfterUpgrade() public { _testRegularL2Upgrade(BNB); }
    // zkSync fork incompatible with Foundry's deal/staticcall — batch verified manually
    // function testZksyncAfterUpgrade() public { _testRegularL2Upgrade(ZKSYNC); }
    function testSonicAfterUpgrade() public { _testRegularL2Upgrade(SONIC); }
    function testHyperevmAfterUpgrade() public { _testRegularL2Upgrade(HYPEREVM); }
    function testScrollAfterUpgrade() public { _testRegularL2Upgrade(SCROLL); }
    function testBlastAfterUpgrade() public { _testRegularL2Upgrade(BLAST); }
    function testModeAfterUpgrade() public { _testRegularL2Upgrade(MODE); }
    function testMorphAfterUpgrade() public { _testRegularL2Upgrade(MORPH); }
    function testSwellAfterUpgrade() public { _testRegularL2Upgrade(SWELL); }

    // ================================================================
    //                    Timelocked L2 chains
    // ================================================================

    function testMonadTimelockAfterUpgrade() public { _testTimelockL2Upgrade(MONAD); }
    function testPlasmaTimelockAfterUpgrade() public { _testTimelockL2Upgrade(PLASMA); }
    function testInkTimelockAfterUpgrade() public { _testTimelockL2Upgrade(INK); }
    function testStableTimelockAfterUpgrade() public {
        vm.createSelectFork(STABLE.RPC_URL);
        console.log("=== stable FORK [TIMELOCK] (chainId: 988) ===");

        address safe = STABLE.L2_CONTRACT_CONTROLLER_SAFE;

        // Stable bridge is already unpaused, so SecurityUpgrade only has DVN config
        executeGnosisTransactionBundle("./output/stable-SecurityUpgrade.json", safe);
        console.log("  SecurityUpgrade (DVN) executed");

        executeGnosisTransactionBundle("./output/stable-TimelockSchedule.json", safe);
        console.log("  TimelockSchedule executed");

        vm.warp(block.timestamp + 3 days);

        executeGnosisTransactionBundle("./output/stable-TimelockExecute.json", safe);
        console.log("  TimelockExecute executed (after 3-day warp)");

        address sender = address(0xBEEF);
        deal(STABLE.L2_OFT, sender, 5 ether);
        _simulateSend(IOFT_Send(STABLE.L2_OFT), L1_EID, sender, "stable->ETH");
        console.log("  All stable sends succeeded");
    }
}
