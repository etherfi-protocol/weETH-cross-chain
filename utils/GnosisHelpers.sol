// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/Strings.sol";


contract GnosisHelpers is Test {

    /**
     * @dev Simulations the execution of a gnosis transaction bundle on the current fork
     * @param transactionPath The path to the transaction bundle json file
     * @param sender The address of the gnosis safe that will execute the transaction
     */
    function executeGnosisTransactionBundle(string memory transactionPath, address sender) public {
        string memory json = vm.readFile(transactionPath);
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", Strings.toString(i), "]")); i++) {
            address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].to"));
            uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].data"));

            vm.prank(sender);
            (bool success,) = address(to).call{value: value}(data);
            require(success, "Transaction failed");
        }
    }


    // Get the gnosis transaction header
    function _getGnosisHeader(string memory chainId) internal pure returns (string memory) {
        return string.concat('{"chainId":"', chainId, '","meta": { "txBuilderVersion": "1.16.5" }, "transactions": [');
    }

    // Create a gnosis transaction
    // ether sent value is always 0 for our usecase
    function _getGnosisTransaction(string memory to, string memory data, bool isLast) internal pure returns (string memory) {
        string memory suffix = isLast ? ']}' : ',';
        return string.concat('{"to":"', to, '","value":"0","data":"', data, '"}', suffix);
    }

    // Helper function to convert bytes to hex strings 
    // soldity encodes returns a bytes object and this must be converted to a hex string to be used in gnosis transactions
    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    // Helper function to convert an address to a hex string of the bytes
    function addressToHex(address addr) public pure returns (string memory) {
        return iToHex(abi.encodePacked(addr));
    }

}
