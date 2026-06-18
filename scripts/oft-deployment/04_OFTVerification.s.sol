// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import "forge-std/Test.sol";
import "../../contracts/EtherFiTimelock.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "../../contracts/EtherfiOFTUpgradeable.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../ContractCodeChecker.s.sol";

// forge script scripts/oft-deployment/04_OFTVerification.s.sol:verifyOFT --via-ir
contract verifyOFT is ContractCodeChecker, Script, L2Constants, Test {

    function run() public {
        vm.createSelectFork(DEPLOYMENT_RPC_URL);

        console2.log("#1. Verification of [OFT implementation] bytecode...");
        EtherfiOFTUpgradeable tmpOFT = new EtherfiOFTUpgradeable(DEPLOYMENT_LZ_ENDPOINT);
        verifyContractByteCodeMatch(DEPLOYMENT_OFT_IMPL, address(tmpOFT));

        console2.log("#2. Verification of [OFT proxy] bytecode...");
        address INITIAL_OWNER = DEPLOYER_ADDRESS;
        TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(
            DEPLOYMENT_OFT_IMPL,
            INITIAL_OWNER,
            abi.encodeWithSelector(
            EtherfiOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, DEPLOYER_ADDRESS)
        );
        verifyContractByteCodeMatch(DEPLOYMENT_OFT, address(tmpProxy));

        // below the expected roles are verified; see notion for documentation on expected roles
        // https://www.notion.so/etherfi/weETH-Cross-Chain-L2-Roles-11ab09527c4380148ed5ec6a4f869677
        console2.log("#3. Asserting all roles are correct..\n");

        EtherfiOFTUpgradeable oft = EtherfiOFTUpgradeable(DEPLOYMENT_OFT);
        LZEndpoint endpoint = LZEndpoint(DEPLOYMENT_LZ_ENDPOINT);

        // verify the proxy admin is the correct address:
        address proxyAdminAddress = address(uint160(uint256(vm.load(DEPLOYMENT_OFT, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))));
        assertEq(proxyAdminAddress, DEPLOYMENT_PROXY_ADMIN_CONTRACT);

        assertEq(ProxyAdmin(DEPLOYMENT_PROXY_ADMIN_CONTRACT).owner(), L2_TIMELOCK);

        assertEq(oft.owner(), L2_TIMELOCK);

        address[] memory pauserHolders = new address[](1);
        pauserHolders[0] = PAUSER_EOA;
        assertEq(oft.roleHolders(oft.PAUSER_ROLE()).length, 1);
        assertEq(oft.roleHolders(oft.PAUSER_ROLE())[0], PAUSER_EOA);

        address[] memory unpauserHolders = new address[](1);
        unpauserHolders[0] = DEPLOYMENT_CONTRACT_CONTROLLER;
        assertEq(oft.roleHolders(oft.UNPAUSER_ROLE()).length, 1);
        assertEq(oft.roleHolders(oft.UNPAUSER_ROLE())[0], DEPLOYMENT_CONTRACT_CONTROLLER);

        assertEq(endpoint.delegates(DEPLOYMENT_OFT), DEPLOYMENT_CONTRACT_CONTROLLER);

        console2.log("All roles are correct!\n");

        console2.log("#4. verify timelock bytecode and roles..\n");
        address[] memory controller = new address[](1);
        controller[0] = DEPLOYMENT_CONTRACT_CONTROLLER;
        EtherFiTimelock timelockTest = new EtherFiTimelock(3 days, controller, controller, DEPLOYMENT_OFT);
        verifyContractByteCodeMatch(L2_TIMELOCK, address(timelockTest));

        EtherFiTimelock timelock = EtherFiTimelock(payable(L2_TIMELOCK));
        assertEq(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), L2_TIMELOCK), true);
        assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(), DEPLOYMENT_CONTRACT_CONTROLLER), true);
        assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(), DEPLOYMENT_CONTRACT_CONTROLLER), true);
        assertEq(timelock.hasRole(timelock.CANCELLER_ROLE(), DEPLOYMENT_CONTRACT_CONTROLLER), true);

        console2.log("All roles are correct!\n");

        // #5. New-policy security-config verification.
        // Only runs when the registry provides an explicit peer allow-list (peerEids length > 0).
        // Verifies: 4-of-4 DVNs @ 45 confirmations on send+receive lib, enforced options (170k gas),
        // and per-pathway inbound/outbound rate limits — all sourced from the registry.
        if (DEPLOYMENT_PEER_EIDS.length > 0) {
            console2.log("#5. Verifying new-policy security config (4-of-4 DVNs, per-pathway limits)..\n");

            address[4] memory dvns = DEPLOYMENT_DVNS;
            bytes memory expectedUln = LayerZeroHelpers._getExpectedUln4(dvns);
            bytes memory expectedOptions = hex"00030100110100000000000000000000000000029810";
            ILayerZeroEndpointV2 lzEndpoint = ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT);

            for (uint256 i = 0; i < DEPLOYMENT_PEER_EIDS.length; i++) {
                uint32 peerEid = DEPLOYMENT_PEER_EIDS[i];

                // ULN config — send lib (requiredDVNCount=4, confirmations=45)
                assertEq(
                    lzEndpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_SEND_LIB_302, peerEid, 2),
                    expectedUln,
                    "SEND ULN config mismatch"
                );
                // ULN config — receive lib
                assertEq(
                    lzEndpoint.getConfig(DEPLOYMENT_OFT, DEPLOYMENT_RECEIVE_LIB_302, peerEid, 2),
                    expectedUln,
                    "RECEIVE ULN config mismatch"
                );

                // Enforced options — msgType 1 & 2 (170k gas)
                assertEq(oft.enforcedOptions(peerEid, 1), expectedOptions, "enforcedOptions(1) mismatch");
                assertEq(oft.enforcedOptions(peerEid, 2), expectedOptions, "enforcedOptions(2) mismatch");

                // Per-pathway rate limits (from registry peerLimits/peerWindows)
                (,, uint256 inLimit, uint256 inWindow) = oft.inboundRateLimits(peerEid);
                assertEq(inLimit,  DEPLOYMENT_PEER_LIMITS[i],  "inbound limit mismatch");
                assertEq(inWindow, DEPLOYMENT_PEER_WINDOWS[i], "inbound window mismatch");

                (,, uint256 outLimit, uint256 outWindow) = oft.outboundRateLimits(peerEid);
                assertEq(outLimit,  DEPLOYMENT_PEER_LIMITS[i],  "outbound limit mismatch");
                assertEq(outWindow, DEPLOYMENT_PEER_WINDOWS[i], "outbound window mismatch");

                console2.log("  peer EID verified:", peerEid);
            }

            console2.log("New-policy security config: all assertions passed!\n");
        }
    }
}

// allows us to interface with the delegates function that isn't defined in the ILayerZeroEndpointV2 interface
interface LZEndpoint {
    function delegates(address) external view returns (address);
}
