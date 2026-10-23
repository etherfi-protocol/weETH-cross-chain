// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {EtherfiOFTUpgradeable} from "../../contracts/EtherfiOFTUpgradeable.sol";
import {EtherfiOFTAdapterUpgradeable} from "../../contracts/EtherFiOFTAdapterUpgradeable.sol";

interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(bytes32 guardedSalt) external view returns (address);
}

/**
 * @notice Deploys the OFT controls implementation for one chain through the CREATE3 factory, so the
 * implementation lands at the same address on every chain. The constructor takes the chain's LayerZero
 * endpoint, so the code differs per endpoint address but the address does not.
 *
 *   TARGET_CHAIN=base forge script scripts/oft-controls/DeployImpl.s.sol --rpc-url <rpc> --broadcast
 *
 * Reads the endpoint from registry/chains.json. `ethereum` deploys the adapter, every other chain the L2 token.
 * Run without --broadcast to print the address it would deploy to. Safe to run twice: it skips a chain whose
 * implementation already exists.
 */
contract DeployImpl is Script {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address internal constant L1_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    bytes32 internal constant L2_SALT = keccak256("EtherfiOFTUpgradeable-impl-controls-v1");
    bytes32 internal constant ADAPTER_SALT = keccak256("EtherfiOFTAdapterUpgradeable-impl-controls-v1");

    function run() external returns (address impl) {
        string memory chain = vm.envString("TARGET_CHAIN");
        string memory json = vm.readFile("registry/chains.json");
        address endpoint = vm.parseJsonAddress(json, string.concat(".", chain, ".L2_ENDPOINT"));
        bool adapter = keccak256(bytes(chain)) == keccak256("ethereum");

        bytes32 salt = adapter ? ADAPTER_SALT : L2_SALT;
        // CreateX hashes a salt that is neither zero-prefixed nor sender-prefixed, so the address ignores the sender.
        impl = CREATEX.computeCreate3Address(keccak256(abi.encode(salt)));
        console.log("chain", chain);
        console.log("endpoint", endpoint);
        console.log("implementation", impl);

        if (impl.code.length != 0) {
            console.log("already deployed, skipping");
            _check(impl, endpoint, adapter);
            return impl;
        }

        bytes memory initCode = adapter
            ? abi.encodePacked(type(EtherfiOFTAdapterUpgradeable).creationCode, abi.encode(L1_WEETH, endpoint))
            : abi.encodePacked(type(EtherfiOFTUpgradeable).creationCode, abi.encode(endpoint));

        vm.startBroadcast();
        address deployed = CREATEX.deployCreate3(salt, initCode);
        vm.stopBroadcast();

        require(deployed == impl, "deployed address differs from the predicted one");
        _check(impl, endpoint, adapter);
    }

    /// @dev Reads the immutables back so a wrong endpoint or token cannot slip through.
    function _check(address impl, address endpoint, bool adapter) internal view {
        require(impl.code.length != 0, "no code at the implementation");
        (bool ok, bytes memory ret) = impl.staticcall(abi.encodeWithSignature("endpoint()"));
        require(ok && abi.decode(ret, (address)) == endpoint, "implementation endpoint mismatch");
        (ok, ret) = impl.staticcall(abi.encodeWithSignature("decimalConversionRate()"));
        require(ok && abi.decode(ret, (uint256)) == 1e12, "unexpected decimal conversion rate");
        if (adapter) {
            (ok, ret) = impl.staticcall(abi.encodeWithSignature("token()"));
            require(ok && abi.decode(ret, (address)) == L1_WEETH, "adapter token mismatch");
        }
        console.log("implementation checks passed");
    }
}
