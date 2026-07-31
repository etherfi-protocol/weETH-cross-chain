// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../utils/L2Constants.sol";

contract TargetLoaderTest is Test, L2Constants {
    function test_loadsRobinhoodTarget() public {
        assertEq(uint256(DEPLOYMENT_EID), 30416);
        assertEq(DEPLOYMENT_DVNS.length, 4);
        // DVNs must be sorted ascending (LZ reverts LZ_ULN_Unsorted otherwise)
        for (uint256 i = 1; i < DEPLOYMENT_DVNS.length; i++) {
            assertLt(uint160(DEPLOYMENT_DVNS[i - 1]), uint160(DEPLOYMENT_DVNS[i]));
        }
        // Endpoint address must be non-zero
        assertTrue(DEPLOYMENT_LZ_ENDPOINT != address(0));
        // Send/Receive lib addresses must be non-zero
        assertTrue(DEPLOYMENT_SEND_LIB_302 != address(0));
        assertTrue(DEPLOYMENT_RECEIVE_LIB_302 != address(0));
    }
}
