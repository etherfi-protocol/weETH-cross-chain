// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

contract TransferOwnershipToTimeLock is Script, L2Constants, GnosisHelpers {

    function run() public {

            string memory transferOwnershipToTimelock = iToHex(abi.encodeWithSignature("transferOwnership(address)", L2_TIMELOCK));

            for (uint256 i = 0; i < L2s.length; i++) {
            // Create gnosis transaction with rate limit data
            string memory UpdateRateLimitJson = _getGnosisHeader(L2s[i].CHAIN_ID, L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
            UpdateRateLimitJson = string(abi.encodePacked(UpdateRateLimitJson, _getGnosisTransaction(addressToHex(L2s[i].L2_OFT), transferOwnershipToTimelock, true)));
            vm.writeJson(UpdateRateLimitJson, string.concat("./output/", L2s[i].NAME, "-AddTimelockAsOwner.json")); 
        }
    }
}
