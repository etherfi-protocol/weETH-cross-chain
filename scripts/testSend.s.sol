// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILineaBridge {
    function claimMessageWithProof(
        bytes32[] calldata _proof,
        uint256 _messageNumber,
        uint32 _leafIndex,
        address _from,
        address _to,
        uint256 _fee,
        uint256 _value,
        address _feeRecipient,
        bytes32 _merkleRoot,
        bytes calldata _data
    ) external;
}

contract SimulationLineaClaim {

    address public lineaBridge = 0xd19d4B5d358258f05D7B411E21A1460D11B0876F;

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

    function executeLineaClaim() public {
        ILineaBridge linea = ILineaBridge(lineaBridge);

        bytes32 [oai_citation:1,Error](data:text/plain;charset=utf-8,Unable%20to%20find%20metadata);
        proof[0] = hash1;
        proof[1] = hash2;
        proof[2] = hash3;
        proof[3] = hash4;
        proof[4] = hash5;

        linea.claimMessageWithProof(proof, messageNumber, leafIndex, from, to, fee, value, feeRecipient, merkleRoot, data);
    }
}

