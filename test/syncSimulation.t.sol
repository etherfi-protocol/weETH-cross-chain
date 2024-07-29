// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../utils/Constants.sol";

interface ILineaBridge {
    struct ClaimMessageWithProofParams {
        bytes32[] proof;
        uint256 messageNumber;
        uint32 leafIndex;
        address from;
        address to;
        uint256 fee;
        uint256 value;
        address payable feeRecipient;
        bytes32 merkleRoot;
        bytes data;
    }
    function claimMessageWithProof(
        ClaimMessageWithProofParams calldata _params
    ) external;
}

contract simulationLineaClaim is Test, Constants {

    address public lineaBridge = 0xd19d4B5d358258f05D7B411E21A1460D11B0876F;

    // linea claim to simulation
    // https://lineascan.build/tx/0x768eb296871217695707514be5dba2feacff972cfb97ec262f0e32eeb5c2712e
    // inputs to claim withdraw:
    bytes32 public hash1 = 0x96e53ee83dd412b01dcebef3567a933af9b92dfdd6e4a3185f0ce4c39434472f;
    bytes32 public hash2 = 0xb4b48a80cad9c721f82850fe01a44998f3c79c08d9497667e72605616db2496c;
    bytes32 public hash3 = 0x86d0810861a37553eba5d63e043c23e5b3bbdef52e25bfcf517dfbe118050df5;
    bytes32 public hash4 = 0xac0dcbaabc79d87d44fd6a529b186425ea9bf2357ae5938fae74941fc99515f3;
    bytes32 public hash5 = 0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344;
    uint256 public messageNumber = 70293;
    uint32 public leafIndex = 3;
    address public from = 0x823106E745A62D0C2FC4d27644c62aDE946D9CCa;
    address public to = 0x6F149F8bf1CB0245e70171c9972059C22294aa35;
    uint256 public fee = 0;
    uint256 public value = 3406189885903122445713;
    address public feeRecipient = 0x0000000000000000000000000000000000000000;
    bytes32 public merkleRoot = 0x4730e9b00dfaf7c89492b61230b26eaff31e8ef6ab23db443ce220d6500f3ebe;
    bytes public data = hex"3a69197e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000075e7bc2482e66ce1739e681c6e2c74e2280bd5a3f1c55ab738a9b9346c6bbebbcc9c000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000b8a66166761fefb5910000000000000000000000000000000000000000000000b0fdc1ebe8c6faa00d";

    function test_LineaClaim() public {
        vm.createSelectFork("https://mainnet.gateway.tenderly.co");
        ILineaBridge linea = ILineaBridge(lineaBridge);
        IERC20 lineaDummyToken = IERC20(LINEA.L1_DUMMY_TOKEN);

        bytes32[] memory proof = new bytes32[](5);
        proof[0] = hash1;
        proof[1] = hash2;
        proof[2] = hash3;
        proof[3] = hash4;
        proof[4] = hash5;

        ILineaBridge.ClaimMessageWithProofParams memory params = ILineaBridge.ClaimMessageWithProofParams({
            proof: proof,
            messageNumber: messageNumber,
            leafIndex: leafIndex,
            from: from,
            to: to,
            fee: fee,
            value: value,
            feeRecipient: payable(feeRecipient),
            merkleRoot: merkleRoot,
            data: data
        });


        vm.prank(0xC83bb94779c5577AF1D48dF8e2A113dFf0cB127c);

        uint256 vampireDummyTokenBalanceBefore = lineaDummyToken.balanceOf(L1_VAMP);
        uint256 syncPoolEthBalanceBefore = address(L1_SYNC_POOL_ADDRESS).balance;
        uint256 vampireEthBalanceBefore = address(L1_VAMP).balance;

        console.log("Vampire Linea Dummy Token Balance Before:", vampireDummyTokenBalanceBefore / 1 ether);
        console.log("Sync Pool ETH Balance Before:", syncPoolEthBalanceBefore / 1 ether);
        console.log("Vampire ETH Balance Before:", vampireEthBalanceBefore / 1 ether);

        linea.claimMessageWithProof(params);

        uint256 vampireDummyTokenBalanceAfter = lineaDummyToken.balanceOf(L1_VAMP);
        uint256 syncPoolEthBalanceAfter = address(L1_SYNC_POOL_ADDRESS).balance;
        uint256 vampireEthBalanceAfter = address(L1_VAMP).balance;

        console.log("Vampire Linea Dummy Token Balance After:", vampireDummyTokenBalanceAfter / 1 ether);
        console.log("Sync Pool ETH Balance After:", syncPoolEthBalanceAfter / 1 ether);
        console.log("Vampire ETH Balance After:", vampireEthBalanceAfter / 1 ether);

    }
}
