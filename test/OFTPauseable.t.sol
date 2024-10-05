// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../utils/Constants.sol";
import "../contracts/MintableOFTUpgradeable.sol";
import "../utils/LayerZeroHelpers.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


contract TestOFTPausable is Test, Constants, LayerZeroHelpers {
    ConfigPerL2 public TEST_L2;
    address public pauser;
    MintableOFTUpgradeable public oft;


    // test against our existing OFT contract on Optimism
    function setUp() public {
        TEST_L2 = BASE;
        pauser = vm.addr(123);
        oft = MintableOFTUpgradeable(TEST_L2.L2_OFT);
        vm.createSelectFork(TEST_L2.RPC_URL);

        // upgrade existing OFT contract to pauseable version
        ProxyAdmin proxyAdmin = ProxyAdmin(TEST_L2.L2_OFT_PROXY_ADMIN);
        address newImpl = address(new MintableOFTUpgradeable(TEST_L2.L2_ENDPOINT));
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(TEST_L2.L2_OFT), newImpl, "");

        // set pauser role
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.grantRole(oft.PAUSER_ROLE(), pauser);
        vm.stopPrank();
    }

    function test_pauseAccessControl() public {
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, TEST_L2.L2_CONTRACT_CONTROLLER_SAFE, oft.PAUSER_ROLE())
        );
        oft.pauseBridge();
        vm.stopPrank();

        vm.startPrank(pauser);
        oft.pauseBridge();
        vm.stopPrank();

        vm.startPrank(pauser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, pauser)
        );
        oft.unpauseBridge();
        vm.stopPrank();

        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseBridge();
    }

    // testing the pausing functionality against outbound cross chain transfers
    function test_pauseOutbound() public {
        _sendCrossChain(false);

        vm.prank(pauser);
        oft.pauseBridge();

        _sendCrossChain(true);

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseBridge();

        _sendCrossChain(false);
    }

    // testing the pausing functionality against inbound cross chain transfers
    function test_pauseInbound() public {
        _mockCrossChainReceive(false);

        vm.prank(pauser);
        oft.pauseBridge();

        _mockCrossChainReceive(true);

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseBridge();

        _mockCrossChainReceive(false);
    }

    // mock an inbound cross chain transfer from L1
    function _mockCrossChainReceive(bool expectRevert) internal {
        address receiver = vm.addr(1);
        uint256 balanceBefore = oft.balanceOf(receiver);

        // Construct mock inbound transfer message from L1
        Origin memory origin = Origin({
            srcEid: L1_EID,
            sender: _toBytes32(L1_OFT_ADAPTER),
            nonce: 1
        });
        bytes32 _guid = 0x1fb4f4c346dd3904d20a62a68ba66df159e012db8526b776cd5bb07b2f80f20e;
        bytes32 _sendTo = _toBytes32(receiver);
        uint64 _amountShared = 10 ether;
        bytes memory _message = abi.encodePacked(_sendTo, _amountShared);

        vm.prank(TEST_L2.L2_ENDPOINT);
        if (expectRevert) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        }
        oft.lzReceive(origin, _guid, _message, address(0), "");

        uint256 balanceAfter = oft.balanceOf(receiver);
        if (expectRevert) {
            assertTrue(balanceAfter == balanceBefore);
        } else {
            assertTrue(balanceAfter > balanceBefore);
        }
    }

    // helper function to simulate cross chain transfers being emitted from this current test L2
    function _sendCrossChain(bool expectRevert) internal {
        address weETH = address(oft);
        address sender = vm.addr(1);
        uint256 amount = 1 ether;

        vm.deal(sender, 100 ether);
        deal(address(weETH), address(sender), amount);

        vm.prank(sender);
        IERC20(weETH).approve(weETH, amount);
        SendParam memory param = SendParam({
            dstEid: 30101,
            to: _toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });

        IOFT oftInterface = IOFT(weETH);
        MessagingFee memory fee = oftInterface.quoteSend(param, false);

        if (expectRevert) {
            vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        }
        vm.prank(sender);
        oftInterface.send{value: fee.nativeFee}(
            param,
            fee,
            sender
        );
    }


}

