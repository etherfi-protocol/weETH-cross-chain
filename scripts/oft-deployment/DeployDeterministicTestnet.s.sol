// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../interfaces/ICreate3Deployer.sol";

/**
 * @title DeployDeterministicTestnet
 * @notice Minimal standalone script that proves CREATE3 determinism on OP Sepolia.
 *
 * Deploys OFT implementation + OFT proxy + Timelock via the CreateX factory using
 * the SAME salts and creation-code construction as the production 01_OFTConfigure.s.sol
 * script, then asserts each address equals the canonical cross-chain address.
 *
 * Fork simulation (no key, no broadcast):
 *   forge script scripts/oft-deployment/DeployDeterministicTestnet.s.sol \
 *     --fork-url https://sepolia.optimism.io -vvv
 *
 * Real broadcast (fund the sender first):
 *   forge script scripts/oft-deployment/DeployDeterministicTestnet.s.sol \
 *     --rpc-url https://sepolia.optimism.io \
 *     --broadcast \
 *     --ledger \
 *     --sender <YOUR_DEPLOYER_ADDRESS> \
 *     --via-ir \
 *     -vvv
 *   # OR replace --ledger --sender with --private-key <KEY>
 *   # Make sure the deployer is funded with OP Sepolia ETH for gas.
 */
contract DeployDeterministicTestnet is Script {

    // -------------------------------------------------------------------------
    // Constants — all hardcoded; no L2Constants inheritance to avoid
    // TARGET_CHAIN registry requirement that doesn't exist for OP Sepolia.
    // -------------------------------------------------------------------------

    ICreate3Deployer private constant CREATE3 =
        ICreate3Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address private constant OP_SEPOLIA_ENDPOINT =
        0x6EDCE65403992e310A62460808c4b910D972f10f;

    // Canonical cross-chain addresses (same on every chain due to CREATE3)
    address private constant CANON_IMPL    = 0x08DB0DB9b5F2dcbBFDc26FF411FB2026e81DA748;
    address private constant CANON_PROXY   = 0xA3D68b74bF0528fdD07263c60d6488749044914b;
    address private constant CANON_TIMELOCK = 0x851Dd540f4D2Ec78120De0a0cc87B21EdE5Df5C6;

    // Token constants (from L2Constants)
    string private constant TOKEN_NAME   = "Wrapped eETH";
    string private constant TOKEN_SYMBOL = "weETH";

    // -------------------------------------------------------------------------
    // run()
    // -------------------------------------------------------------------------

    function run() public {
        // Guard: verify CreateX is deployed on this fork
        uint256 s;
        address f = address(CREATE3);
        assembly { s := extcodesize(f) }
        require(s > 0, "CreateX missing: is this an OP Sepolia fork?");

        vm.startBroadcast();

        // ------------------------------------------------------------------
        // 1. Deploy OFT Implementation
        //    Mirrors: abi.encodePacked(type(EtherfiOFTUpgradeable).creationCode,
        //                              abi.encode(DEPLOYMENT_LZ_ENDPOINT))
        // ------------------------------------------------------------------
        bytes memory implCreationCode = abi.encodePacked(
            type(EtherfiOFTUpgradeable).creationCode,
            abi.encode(OP_SEPOLIA_ENDPOINT)
        );

        address impl = CREATE3.deployCreate3(
            keccak256("EtherfiOFTUpgradeable-impl"),
            implCreationCode
        );

        console.log("OFT implementation:", impl);
        require(impl == CANON_IMPL, "impl != canonical");

        // ------------------------------------------------------------------
        // 2. Deploy OFT Proxy
        //    Mirrors: abi.encodePacked(type(TransparentUpgradeableProxy).creationCode,
        //                              abi.encode(impl, scriptDeployer,
        //                                         abi.encodeWithSelector(initialize, name, sym, owner)))
        //    Uses msg.sender as temporary admin/owner — address is salt-determined,
        //    constructor args don't affect the deployed address.
        // ------------------------------------------------------------------
        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                msg.sender,
                abi.encodeWithSelector(
                    EtherfiOFTUpgradeable.initialize.selector,
                    TOKEN_NAME,
                    TOKEN_SYMBOL,
                    msg.sender
                )
            )
        );

        address proxy = CREATE3.deployCreate3(
            keccak256("EtherfiOFTUpgradeable-proxy"),
            proxyCreationCode
        );

        console.log("OFT proxy:", proxy);
        require(proxy == CANON_PROXY, "proxy != canonical");

        // ------------------------------------------------------------------
        // 3. Deploy Timelock
        //    Mirrors: abi.encodePacked(type(EtherFiTimelock).creationCode,
        //                              abi.encode(3 days, controller, controller, address(0)))
        //    Uses msg.sender as placeholder controller — address is salt-determined.
        // ------------------------------------------------------------------
        address[] memory controllerArray = new address[](1);
        controllerArray[0] = msg.sender;

        bytes memory timelockCreationCode = abi.encodePacked(
            type(EtherFiTimelock).creationCode,
            abi.encode(3 days, controllerArray, controllerArray, address(0))
        );

        address timelock = CREATE3.deployCreate3(
            keccak256("EtherFiTimelock"),
            timelockCreationCode
        );

        console.log("Timelock:", timelock);
        require(timelock == CANON_TIMELOCK, "timelock != canonical");

        vm.stopBroadcast();

        console.log("");
        console.log("All three addresses match canonical. CREATE3 determinism confirmed on OP Sepolia.");
    }
}
