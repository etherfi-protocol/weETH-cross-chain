// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

interface IGnosisSafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes calldata initializer, uint256 saltNonce)
        external
        returns (address);
}

/// @notice Deterministically deploys the canonical controller Safe
///         `0x7a00657a…` (GnosisSafe 1.3.0, 2-of-5) using the exact `setup`
///         initializer recovered from its original Base creation tx
///         (0x373df201c7de3e4091b5cc3c677c1637139d92ceaeec2792e02e324cfee9fead).
///         The address depends only on (factory, singleton, initializer,
///         saltNonce) — never the deployer — so it reproduces on any chain.
///
///         Deploys the original 2-of-5; migrate to the mesh-standard 4-of-7
///         afterward via a 3CP signed by the original owners
///         (`make-3cp-folder.mjs --type safe-migration`).
///
/// forge script scripts/oft-deployment/DeployControllerSafe.s.sol:DeployControllerSafe \
///   --rpc-url <rpc> --ledger --sender 0x8D5AAc5d3d5cda4c404fA7ee31B0822B648Bb150 --broadcast
contract DeployControllerSafe is Script {
    IGnosisSafeProxyFactory private constant SAFE_FACTORY =
        IGnosisSafeProxyFactory(0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC);
    address private constant SAFE_SINGLETON = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    uint256 private constant SAFE_SALT_NONCE = 0;
    address private constant CANON_CONTROLLER_SAFE = 0x7a00657a45420044bc526B90Ad667aFfaee0A868;

    // Recovered initializer (484 bytes): setup(owners=[0x5c8c76,0x4507cf,0x0e706A,
    // 0xD31074,0x566E58], threshold=2, to=0, data=0x, fallbackHandler=0x017062a1…,
    // paymentToken=0, payment=0, paymentReceiver=0).
    bytes private constant SAFE_INITIALIZER =
        hex"b63e800d"
        hex"0000000000000000000000000000000000000000000000000000000000000100"
        hex"0000000000000000000000000000000000000000000000000000000000000002"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"00000000000000000000000000000000000000000000000000000000000001c0"
        hex"000000000000000000000000017062a1de2fe6b99be3d9d37841fed19f573804"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000005"
        hex"0000000000000000000000005c8c76f2e990f194462dc5f8a8c76ba16966ed42"
        hex"0000000000000000000000004507cfb4b077d5dbddd520c701e30173d5b59fad"
        hex"0000000000000000000000000e706a98f414f49a412107641c0820b0153ff5dc"
        hex"000000000000000000000000d31074937b28f65db4eeb243916883e335261650"
        hex"000000000000000000000000566e58ac0f2c4bcaf6de63760c56cc3f825c48f5"
        hex"0000000000000000000000000000000000000000000000000000000000000000";

    function run() public {
        require(address(SAFE_FACTORY).code.length > 0, "Safe factory not deployed on this chain");

        if (CANON_CONTROLLER_SAFE.code.length > 0) {
            console.log("Controller Safe already deployed at", CANON_CONTROLLER_SAFE);
            return;
        }

        vm.startBroadcast();
        address safe = SAFE_FACTORY.createProxyWithNonce(SAFE_SINGLETON, SAFE_INITIALIZER, SAFE_SALT_NONCE);
        vm.stopBroadcast();

        require(safe == CANON_CONTROLLER_SAFE, "Safe address != canonical 0x7a00657a");
        console.log("Controller Safe deployed (2-of-5):", safe);
        console.log("Next: 03_OFTOwnershipTransfer (handoff), then migrate to 4-of-7 via 3CP.");
    }
}
