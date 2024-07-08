// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../utils/Constants.sol";
import "../contracts/PausableMintableOFTUpgradeable.sol";
import "../contracts/CustomPausableUpgradeable.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


contract TestPausable is Test, Constants {
    ConfigPerL2 public TEST_L2;

    // Configuration variable to choose which L2 to test against
    function setUp() public {
        TEST_L2 = OP;
        vm.createSelectFork(TEST_L2.RPC_URL);
    }

    // Asserts that the existing configurations were not altered during the upgrade
    function testUpgrade() public {
        checkOFTParameters();
        upgradeOFT();
        checkOFTParameters();
    }

    // Asserts that only the ADMIN_ROLE can 
    function testPauseControl() public {
        upgradeOFT();

        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

        // Test pausing of cross chain
        vm.expectRevert();
        oft.pauseCrossChain();
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseCrossChain();
        vm.expectRevert();
        oft.unpauseCrossChain();

        // Cross chain should be paused but movement should not be
        assertTrue(oft.paused(oft.PAUSED_CROSS_CHAIN()));
        assertFalse(oft.paused(oft.PAUSED_MOVEMENT()));

        // Test pausing of movement
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        vm.expectRevert(
            abi.encodeWithSelector(CustomPausableUpgradeable.ExpectedPause.selector, oft.PAUSED_MOVEMENT())
        );
        oft.unpauseMovement();
        oft.pauseMovement();

        // all pause states should be true
        assertTrue(oft.paused(oft.PAUSED_CROSS_CHAIN()));
        assertTrue(oft.paused(oft.PAUSED_MOVEMENT()));

        oft.unpauseCrossChain();

        // movement should be paused but cross chain should not be
        assertFalse(oft.paused(oft.PAUSED_CROSS_CHAIN()));
        assertTrue(oft.paused(oft.PAUSED_MOVEMENT()));

        oft.unpauseMovement();

        // all pause states should be false
        assertFalse(oft.paused(oft.PAUSED_CROSS_CHAIN()));
        assertFalse(oft.paused(oft.PAUSED_MOVEMENT()));
    }

    function testPauseOutbound() public {
        upgradeOFT();
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

       // Expect success
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, false, oft.PAUSED_CROSS_CHAIN());

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseCrossChain();

        // Expect revert due to paused state
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, true, oft.PAUSED_CROSS_CHAIN());

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseCrossChain();
       
        // Expect success
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, false, oft.PAUSED_CROSS_CHAIN());   
    }

    function testPauseInbound() public {
        upgradeOFT();
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

        // Expect success
        mockCrossChainReceive(false, oft.PAUSED_CROSS_CHAIN());   

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseCrossChain();

        // Expect revert due to paused state
        mockCrossChainReceive(true, oft.PAUSED_CROSS_CHAIN());   

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseCrossChain();

        // Expect success
        mockCrossChainReceive(false, oft.PAUSED_CROSS_CHAIN());   
    }

    function testExternalMint() public {
        upgradeOFT();
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

        address minter = vm.addr(1);
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.grantRole(0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6, minter);

        vm.prank(minter);
        oft.mint(minter, 100 ether);

        assertTrue(oft.balanceOf(minter) == 100 ether);

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseCrossChain();

        vm.expectRevert(
            abi.encodeWithSelector(CustomPausableUpgradeable.EnforcedPause.selector, oft.PAUSED_CROSS_CHAIN())
        );
        vm.prank(minter);
        oft.mint(minter, 100 ether);

        assertTrue(oft.balanceOf(minter) == 100 ether);

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseCrossChain();

        vm.prank(minter);
        oft.mint(minter, 100 ether);

        assertTrue(oft.balanceOf(minter) == 200 ether);
    }

    function testMovementPause() public {
        upgradeOFT();
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

        address sender = vm.addr(123);
        address receiver = vm.addr(456);

        // Just movement flag is set
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseMovement();

        deal(address(oft), address(sender), 100 ether);

        vm.prank(sender);

        // All movements of funds should be paused
        vm.expectRevert(
            abi.encodeWithSelector(CustomPausableUpgradeable.EnforcedPause.selector, oft.PAUSED_MOVEMENT())
        );
        oft.transfer(receiver, 100 ether);
        mockCrossChainReceive(true, oft.PAUSED_MOVEMENT());
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, true, oft.PAUSED_MOVEMENT());

        assertTrue(oft.balanceOf(sender) == 100 ether);
        assertTrue(oft.balanceOf(receiver) == 0);

        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseMovement();

        vm.prank(sender);
        oft.transfer(receiver, 50 ether);

        assertTrue(oft.balanceOf(sender) == 50 ether);
        assertTrue(oft.balanceOf(receiver) == 50 ether);

        // Both flags are set
        vm.startPrank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.pauseCrossChain();
        oft.pauseMovement();
        vm.stopPrank();

        // All movements of funds should be paused
        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(CustomPausableUpgradeable.EnforcedPause.selector, oft.PAUSED_MOVEMENT())
        );
        oft.transfer(receiver, 100 ether);
        mockCrossChainReceive(true, oft.PAUSED_CROSS_CHAIN());   
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, true, oft.PAUSED_CROSS_CHAIN());   

        // Only Cross chain is paused
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        oft.unpauseMovement();

        vm.prank(sender);

        // Onchain transfer should succeed but cross chain should fail
        oft.transfer(receiver, 50 ether);
        mockCrossChainReceive(true, oft.PAUSED_CROSS_CHAIN());
        sendCrossChain(L1_EID, TEST_L2.L2_OFT, 100 ether, true, oft.PAUSED_CROSS_CHAIN());
    }

    // Upgrades the OFT contract to the pausable version
    function upgradeOFT() public {
        ProxyAdmin proxyAdmin = ProxyAdmin(TEST_L2.L2_OFT_PROXY_ADMIN);
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(TEST_L2.L2_OFT)));

        address impl = address(new PausableMintableOFTUpgradeable(TEST_L2.L2_ENDPOINT));
        vm.prank(TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(impl), "");
    }

    // Verifies the configuration of the OFT contract
    function checkOFTParameters() public {
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);

        console.log("confirming that the chain agnostic configuration is correct");
        assertEq(address(oft.endpoint()), TEST_L2.L2_ENDPOINT);
        assertEq(oft.symbol(), TOKEN_SYMBOL);
        assertEq(oft.name(), TOKEN_NAME);
        assertEq(oft.owner(), TEST_L2.L2_CONTRACT_CONTROLLER_SAFE);

        console.log("confirming that L2 -> L1 configuration is correct");
        assertTrue(oft.isPeer(L1_EID, _toBytes32(L1_OFT_ADAPTER)));
        (,,uint256 limit, uint256 window) = oft.rateLimits(L1_EID);
        assertEq(limit, 200 ether);
        assertEq(window, 4 hours);
        assertEq(oft.enforcedOptions(L1_EID, 1), hex"000301001101000000000000000000000000000f4240");
        assertEq(oft.enforcedOptions(L1_EID, 2), hex"000301001101000000000000000000000000000f4240");

        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(TEST_L2.L2_ENDPOINT);
        assertEq(endpoint.getConfig(TEST_L2.L2_OFT, TEST_L2.SEND_302, L1_EID, 2), _getExpectedUln(TEST_L2.LZ_DVN[0], TEST_L2.LZ_DVN[1]));
        assertEq(endpoint.getConfig(TEST_L2.L2_OFT, TEST_L2.RECEIVE_302, L1_EID, 2), _getExpectedUln(TEST_L2.LZ_DVN[0], TEST_L2.LZ_DVN[1]));

        for (uint i = 0; i < L2s.length; i++) {
            if (L2s[i].L2_EID == TEST_L2.L2_EID) {
                // Skip the current L2 that we are testing against
                continue;
            }

            console.log("confirming that deployment -> %s configuration is correct", L2s[i].NAME);
            assertTrue(oft.isPeer(L2s[i].L2_EID, _toBytes32(L2s[i].L2_OFT)));
            (,,limit, window) = oft.rateLimits(L2s[i].L2_EID);
            assertEq(limit, 200 ether);
            assertEq(window, 4 hours);
            assertEq(oft.enforcedOptions(L2s[i].L2_EID, 1), hex"000301001101000000000000000000000000000f4240"); 
            assertEq(oft.enforcedOptions(L2s[i].L2_EID, 2), hex"000301001101000000000000000000000000000f4240");


            assertEq(endpoint.getConfig(TEST_L2.L2_OFT, TEST_L2.SEND_302, L2s[i].L2_EID, 2), _getExpectedUln(TEST_L2.LZ_DVN[0], TEST_L2.LZ_DVN[1]));
            assertEq(endpoint.getConfig(TEST_L2.L2_OFT, TEST_L2.RECEIVE_302, L2s[i].L2_EID, 2), _getExpectedUln(TEST_L2.LZ_DVN[0], TEST_L2.LZ_DVN[1]));
        }
    }

    // A helper function to send weETH cross chain
    function sendCrossChain(uint32 dstEid, address oft, uint256 amount, bool expectRevert, uint8 pauseIndex) public {
        address weETH = oft;
        if (block.chainid == 1) { 
            weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        }
        address sender = vm.addr(1);
        vm.deal(sender, 100 ether);
        deal(address(weETH), address(sender), amount);

        vm.prank(sender);
        IERC20(weETH).approve(oft, amount);

        SendParam memory param = SendParam({
            dstEid: dstEid,
            to: _toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });

        IOFT oftInterface = IOFT(oft);
        MessagingFee memory fee = oftInterface.quoteSend(param, false);
        console.log("expectedFee:", fee.nativeFee);

        if (expectRevert) {
            vm.expectRevert(abi.encodeWithSelector(CustomPausableUpgradeable.EnforcedPause.selector, pauseIndex));
        }
        vm.prank(sender);
        oftInterface.send{value: fee.nativeFee}(
            param,
            fee,
            sender
        );
    }

    // Mock inbound transfer from L1
    function mockCrossChainReceive(bool expectRevert, uint8 pauseIndex) public {
        PausableMintableOFTUpgradeable oft = PausableMintableOFTUpgradeable(TEST_L2.L2_OFT);
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
            vm.expectRevert(abi.encodeWithSelector(CustomPausableUpgradeable.EnforcedPause.selector, pauseIndex));
        }
        oft.lzReceive(origin, _guid, _message, address(0), "");

        uint256 balanceAfter = oft.balanceOf(receiver);

        if (expectRevert) {
            assertTrue(balanceAfter == balanceBefore);
        } else {
            assertTrue(balanceAfter > balanceBefore);
        }
    }
    
    // Converts an address to bytes32
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Decode bytes into a UlnConfig struct
    function _getExpectedUln(address lzDvn, address nethermindDvn) public pure returns (bytes memory) {
        address[] memory requiredDVNs = new address[](2);

        if (lzDvn > nethermindDvn) {
            requiredDVNs[0] = nethermindDvn;
            requiredDVNs[1] = lzDvn;
        } else {
            requiredDVNs[0] = lzDvn;
            requiredDVNs[1] = nethermindDvn;
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        return abi.encode(ulnConfig);
    }
}
