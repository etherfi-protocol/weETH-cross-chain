// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";


contract ContractCodeChecker {

    event ByteMismatchSegment(
        uint256 startIndex,
        uint256 endIndex,
        bytes aSegment,
        bytes bSegment
    );

    function compareBytes(bytes memory a, bytes memory b) internal returns (bool) {
        if (a.length != b.length) {
            // Length mismatch, emit one big segment for the difference if that’s desirable
            // or just return false. For clarity, we can just return false here.
            return false;
        }

        uint256 len = a.length;
        uint256 start = 0;
        bool inMismatch = false;
        bool anyMismatch = false;

        for (uint256 i = 0; i < len; i++) {
            bool mismatch = (a[i] != b[i]);
            if (mismatch && !inMismatch) {
                // Starting a new mismatch segment
                start = i;
                inMismatch = true;
            } else if (!mismatch && inMismatch) {
                // Ending the current mismatch segment at i-1
                emitMismatchSegment(a, b, start, i - 1);
                inMismatch = false;
                anyMismatch = true;
            }
        }

        // If we ended with a mismatch still open, close it out
        if (inMismatch) {
            emitMismatchSegment(a, b, start, len - 1);
            anyMismatch = true;
        }

        // If no mismatch segments were found, everything matched
        return !anyMismatch;
    }

    function emitMismatchSegment(
        bytes memory a,
        bytes memory b,
        uint256 start,
        uint256 end
    ) internal {
        // endIndex is inclusive
        uint256 segmentLength = end - start + 1;

        bytes memory aSegment = new bytes(segmentLength);
        bytes memory bSegment = new bytes(segmentLength);

        for (uint256 i = 0; i < segmentLength; i++) {
            aSegment[i] = a[start + i];
            bSegment[i] = b[start + i];
        }

        string memory aHex = bytesToHexString(aSegment);
        string memory bHex = bytesToHexString(bSegment);

        console2.log("- Mismatch segment at index [%s, %s]", start, end);
        console2.logString(string.concat(" - ", aHex));
        console2.logString(string.concat(" - ", bHex));

        emit ByteMismatchSegment(start, end, aSegment, bSegment);
    }

    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        // Every byte corresponds to two hex characters
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    // Compare the full bytecode of two deployed contracts, ensuring a perfect match.
    function verifyFullMatch(bytes memory localBytecode, bytes memory onchainRuntimeBytecode) public {
        console2.log("Verifying full bytecode match...");

        if (compareBytes(localBytecode, onchainRuntimeBytecode)) {
            console2.log("-> Full Bytecode Match: Success\n");
        } else {
            console2.log("-> Full Bytecode Match: Fail\n");
        }
    }

    function verifyPartialMatch(bytes memory localBytecode, bytes memory onchainRuntimeBytecode) public {
        console2.log("Verifying partial bytecode match...");

        // Optionally check length first (not strictly necessary if doing a partial match)
        if (localBytecode.length == 0 || onchainRuntimeBytecode.length == 0) {
            revert("One of the bytecode arrays is empty, cannot verify.");
        }

        // Attempt to trim metadata from both local and on-chain bytecode
        bytes memory trimmedLocal = trimMetadata(localBytecode);
        bytes memory trimmedOnchain = trimMetadata(onchainRuntimeBytecode);

        // If trimmed lengths differ significantly, it suggests structural differences in code
        if (trimmedLocal.length != trimmedOnchain.length) {
            console2.log("Post-trim length mismatch: potential code differences.");
        }

        // Compare trimmed arrays byte-by-byte
        if (compareBytes(trimmedLocal, trimmedOnchain)) {
            console2.log("-> Partial Bytecode Match: Success\n");
        } else {
            console2.log("-> Partial Bytecode Match: Fail\n");
        }
    }

    function verifyLengthMatch(bytes memory localBytecode, bytes memory onchainRuntimeBytecode) public {
        console2.log("Verifying length match...");

        if (localBytecode.length == onchainRuntimeBytecode.length) {
            console2.log("-> Length Match: Success");
        } else {
            console2.log("-> Length Match: Fail");
        }
        console2.log("Bytecode Length: ", localBytecode.length, "\n");
    }

    function verifyContractByteCodeMatchFromAddress(address deployedImpl, address localDeployed) public {
        verifyLengthMatch(deployedImpl.code, localDeployed.code);
        verifyPartialMatch(deployedImpl.code, localDeployed.code);
        // verifyFullMatch(deployedImpl.code, localDeployed.code);
    }

    function verifyContractByteCodeMatchFromByteCode(bytes memory deployedImpl, bytes memory localDeployed) public {
        verifyLengthMatch(deployedImpl, localDeployed);
        verifyPartialMatch(deployedImpl, localDeployed);
        // verifyFullMatch(deployedImpl, localDeployed);
    }

    // Known CBOR patterns for Solidity metadata:
    // "a2 64 73 6f 6c 63" -> a2 (map with 2 pairs), 64 (4-char string), 's' 'o' 'l' 'c'
    // "a2 64 69 70 66 73" -> a2 (map with 2 pairs), 64 (4-char string), 'i' 'p' 'f' 's'
    bytes constant SOLC_PATTERN = hex"a264736f6c63";  // "a2 64 73 6f 6c 63"
    bytes constant IPFS_PATTERN = hex"a26469706673";  // "a2 64 69 70 66 73"

    function trimMetadata(bytes memory code) internal pure returns (bytes memory) {
        uint256 length = code.length;
        if (length < SOLC_PATTERN.length) {
            // Bytecode too short to contain metadata
            return code;
        }

        // Try to find a known pattern from the end.
        // We'll look for either the "solc" pattern or the "ipfs" pattern.
        int256 solcIndex = lastIndexOf(code, SOLC_PATTERN);
        int256 ipfsIndex = lastIndexOf(code, IPFS_PATTERN);

        // Determine which pattern was found later (nearer to the end).
        int256 metadataIndex;
        if (solcIndex >= 0 && ipfsIndex >= 0) {
            metadataIndex = solcIndex > ipfsIndex ? solcIndex : ipfsIndex;
        } else if (solcIndex >= 0) {
            metadataIndex = solcIndex;
        } else if (ipfsIndex >= 0) {
            metadataIndex = ipfsIndex;
        } else {
            // No known pattern found, return code as is
            return code;
        }

        console2.log("Original bytecode length: ", length);
        console2.log("Trimmed metadata from bytecode at index: ", metadataIndex);

        // metadataIndex is where metadata starts
        bytes memory trimmed = new bytes(uint256(metadataIndex));
        for (uint256 i = 0; i < uint256(metadataIndex); i++) {
            trimmed[i] = code[i];
        }
        return trimmed;
    }

    // Helper function: Finds the last occurrence of `pattern` in `data`.
    // Returns -1 if not found, otherwise returns the starting index.
    function lastIndexOf(bytes memory data, bytes memory pattern) internal pure returns (int256) {
        if (pattern.length == 0 || pattern.length > data.length) {
            return -1;
        }

        // Start from the end of `data` and move backward
        for (uint256 i = data.length - pattern.length; /* no condition */; i--) {
            bool matchFound = true;
            for (uint256 j = 0; j < pattern.length; j++) {
                if (data[i + j] != pattern[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) {
                return int256(i);
            }
            if (i == 0) break; // Prevent underflow
        }

        return -1;
    }

}