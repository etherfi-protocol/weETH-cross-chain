// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../utils/L2Constants.sol";

/// Verifies `_loadTarget()` for whatever chain TARGET_CHAIN names, by comparing the loaded values
/// against registry/chains.json itself. The previous version asserted robinhood's EID literally,
/// so it failed for every other TARGET_CHAIN even when the loader was correct.
contract TargetLoaderTest is Test, L2Constants {
    using stdJson for string;

    string json;
    string policy;
    string base; // ".<resolvedKey>."

    function setUp() public {
        json = vm.readFile("registry/chains.json");
        policy = vm.readFile("registry/policy.json");
        base = string.concat(".", _resolvedKey(), ".");
    }

    /// TARGET_CHAIN as the registry knows it, after alias resolution (optimism -> op).
    function _resolvedKey() internal view returns (string memory) {
        string memory key = vm.envOr("TARGET_CHAIN", string(""));
        require(bytes(key).length > 0, "TARGET_CHAIN env var required");
        string memory aliasPath = string.concat(".chainKeyAliases.", key);
        if (!vm.keyExistsJson(json, string.concat(".", key)) && vm.keyExistsJson(policy, aliasPath)) {
            return policy.readString(aliasPath);
        }
        return key;
    }

    function test_loadedTargetMatchesRegistry() public view {
        assertEq(uint256(DEPLOYMENT_EID), json.readUint(string.concat(base, "L2_EID")), "EID mismatch");
        assertEq(DEPLOYMENT_LZ_ENDPOINT, json.readAddress(string.concat(base, "L2_ENDPOINT")), "endpoint mismatch");
        assertEq(DEPLOYMENT_SEND_LIB_302, json.readAddress(string.concat(base, "SEND_302")), "send lib mismatch");
        assertEq(DEPLOYMENT_RECEIVE_LIB_302, json.readAddress(string.concat(base, "RECEIVE_302")), "recv lib mismatch");

        address[] memory expected = json.readAddressArray(string.concat(base, "LZ_DVN"));
        assertEq(DEPLOYMENT_DVNS.length, expected.length, "DVN count mismatch");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(DEPLOYMENT_DVNS[i], expected[i], "DVN mismatch");
        }
    }

    function test_loadedAddressesAreNonZero() public view {
        assertTrue(DEPLOYMENT_LZ_ENDPOINT != address(0), "endpoint is zero");
        assertTrue(DEPLOYMENT_SEND_LIB_302 != address(0), "send lib is zero");
        assertTrue(DEPLOYMENT_RECEIVE_LIB_302 != address(0), "recv lib is zero");
        assertTrue(uint256(DEPLOYMENT_EID) != 0, "EID is zero");
        for (uint256 i = 0; i < DEPLOYMENT_DVNS.length; i++) {
            assertTrue(DEPLOYMENT_DVNS[i] != address(0), "a DVN is zero");
        }
    }

    function test_dvnsAreSortedAscending() public view {
        // LayerZero reverts LZ_ULN_Unsorted on an unsorted required array
        for (uint256 i = 1; i < DEPLOYMENT_DVNS.length; i++) {
            assertLt(uint160(DEPLOYMENT_DVNS[i - 1]), uint160(DEPLOYMENT_DVNS[i]), "DVNs not sorted ascending");
        }
    }

    /// The Canary -> P2P swap retired one DVN per chain. Loading a target that still carries its
    /// retired DVN means the registry is stale and any config generated from it would re-onboard it.
    function test_loadedDvnsExcludeRetiredDvn() public view {
        string memory retiredPath = string.concat(".retiredDvns.", _resolvedKey());
        if (!vm.keyExistsJson(policy, retiredPath)) return; // chain was never on the retired DVN
        address retired = policy.readAddress(retiredPath);
        for (uint256 i = 0; i < DEPLOYMENT_DVNS.length; i++) {
            assertTrue(DEPLOYMENT_DVNS[i] != retired, "loaded DVN set still contains the retired DVN");
        }
    }

    /// The alias table must resolve to real registry keys, or TARGET_CHAIN=optimism silently
    /// resolves to nothing and every loader path fails with a raw parseJson error.
    function test_chainKeyAliasesResolveToRegistryKeys() public view {
        string[] memory aliases = vm.parseJsonKeys(policy, ".chainKeyAliases");
        assertGt(aliases.length, 0, "no aliases defined");
        for (uint256 i = 0; i < aliases.length; i++) {
            string memory target = policy.readString(string.concat(".chainKeyAliases.", aliases[i]));
            assertTrue(
                vm.keyExistsJson(json, string.concat(".", target)),
                string.concat("alias '", aliases[i], "' points at missing registry key '", target, "'")
            );
        }
    }
}
