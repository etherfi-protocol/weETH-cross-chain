// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/native-minting/receivers/L1ScrollReceiverETHUpgradeable.sol";
import "../../contracts/native-minting/DummyTokenUpgradeable.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import "../../interfaces/ICreate3Deployer.sol";
import "../../contracts/native-minting/EtherfiL1SyncPoolETH.sol";
import "../../contracts/libraries/Constants.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// forge script scripts/native-minting-deployment/DeployConfigureL1OPStack.s.sol:DeployConfigureL1OPStack --evm-version "shanghai" --via-ir
contract DeployConfigureL1OPStack is Script, L2Constants, GnosisHelpers {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    function getTargetChain() internal view returns (ConfigPerL2 storage) {
        string memory chain = vm.envString("TARGET_CHAIN");
        bytes32 chainHash = keccak256(bytes(chain));

        if (chainHash == keccak256("op")) return OP;
        if (chainHash == keccak256("scroll")) return SCROLL;
        if (chainHash == keccak256("ink")) return INK;

        revert("DeployConfigureL1OPStack: unknown TARGET_CHAIN");
    }

    function getSalt(ConfigPerL2 storage config, string memory label) internal view returns (bytes32) {
        return keccak256(bytes(string.concat(config.NAME, label)));
    }

    function deployDummyToken(ConfigPerL2 storage config) internal returns (address) {
        address impl = CREATE3.deployCreate3(
            getSalt(config, "DummyTokenImpl"),
            abi.encodePacked(type(DummyTokenUpgradeable).creationCode, abi.encode(uint8(18)))
        );

        string memory tokenName = string.concat(config.NAME, " Dummy ETH");
        string memory tokenSymbol = string.concat(config.NAME, "ETH");

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                L1_TIMELOCK,
                abi.encodeWithSelector(DummyTokenUpgradeable.initialize.selector, tokenName, tokenSymbol, DEPLOYER_ADDRESS)
            )
        );
        address proxy = CREATE3.deployCreate3(getSalt(config, "DummyToken"), proxyCreationCode);
        console.log("DummyToken deployed at:", proxy);
        require(proxy == config.L1_DUMMY_TOKEN, "Dummy Token address mismatch");

        DummyTokenUpgradeable dummyToken = DummyTokenUpgradeable(proxy);
        dummyToken.grantRole(MINTER_ROLE, L1_SYNC_POOL);
        dummyToken.grantRole(DEFAULT_ADMIN_ROLE, L1_CONTRACT_CONTROLLER);
        dummyToken.renounceRole(DEFAULT_ADMIN_ROLE, DEPLOYER_ADDRESS);

        return proxy;
    }

    function deployReceiver(ConfigPerL2 storage config) internal returns (address) {
        address impl = CREATE3.deployCreate3(
            getSalt(config, "ReceiverImpl"),
            type(L1ScrollReceiverETHUpgradeable).creationCode
        );

        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                impl,
                L1_TIMELOCK,
                abi.encodeWithSelector(
                    L1ScrollReceiverETHUpgradeable.initialize.selector,
                    L1_SYNC_POOL,
                    config.L1_MESSENGER,
                    L1_CONTRACT_CONTROLLER
                )
            )
        );
        address proxy = CREATE3.deployCreate3(getSalt(config, "Receiver"), proxyCreationCode);
        console.log("Receiver deployed at:", proxy);
        require(proxy == config.L1_RECEIVER, "Receiver address mismatch");

        return proxy;
    }

    function getTimelockScheduleTransactions(ConfigPerL2 storage config) internal view returns (string memory) {
        string memory txs = _getGnosisHeader("1", L1_TIMELOCK_GNOSIS);

        bytes memory registerTokenData = abi.encodeWithSignature(
            "registerToken(address,address,bool,uint16,uint32,uint32,bool)",
            config.L1_DUMMY_TOKEN, address(0), true, 0, 20_000, 2_000_000, true
        );
        txs = string.concat(txs, _getGnosisScheduleTransaction(L1_VAMP, registerTokenData, false));

        bytes memory setReceiverData = abi.encodeWithSignature("setReceiver(uint32,address)", config.L2_EID, config.L1_RECEIVER);
        txs = string.concat(txs, _getGnosisScheduleTransaction(L1_SYNC_POOL, setReceiverData, false));

        bytes memory setDummyTokenData = abi.encodeWithSignature("setDummyToken(uint32,address)", config.L2_EID, config.L1_DUMMY_TOKEN);
        txs = string.concat(txs, _getGnosisScheduleTransaction(L1_SYNC_POOL, setDummyTokenData, false));

        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", config.L2_EID, LayerZeroHelpers._toBytes32(config.L2_SYNC_POOL));
        txs = string.concat(txs, _getGnosisScheduleTransaction(L1_SYNC_POOL, setPeerData, true));

        return txs;
    }

    function getTimelockExecuteTransactions(ConfigPerL2 storage config) internal view returns (string memory) {
        string memory txs = _getGnosisHeader("1", L1_TIMELOCK_GNOSIS);

        bytes memory registerTokenData = abi.encodeWithSignature(
            "registerToken(address,address,bool,uint16,uint32,uint32,bool)",
            config.L1_DUMMY_TOKEN, address(0), true, 0, 20_000, 2_000_000, true
        );
        txs = string.concat(txs, _getGnosisExecuteTransaction(L1_VAMP, registerTokenData, false));

        bytes memory setReceiverData = abi.encodeWithSignature("setReceiver(uint32,address)", config.L2_EID, config.L1_RECEIVER);
        txs = string.concat(txs, _getGnosisExecuteTransaction(L1_SYNC_POOL, setReceiverData, false));

        bytes memory setDummyTokenData = abi.encodeWithSignature("setDummyToken(uint32,address)", config.L2_EID, config.L1_DUMMY_TOKEN);
        txs = string.concat(txs, _getGnosisExecuteTransaction(L1_SYNC_POOL, setDummyTokenData, false));

        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", config.L2_EID, LayerZeroHelpers._toBytes32(config.L2_SYNC_POOL));
        txs = string.concat(txs, _getGnosisExecuteTransaction(L1_SYNC_POOL, setPeerData, true));

        return txs;
    }

    function getControllerConfigTransactions(ConfigPerL2 storage config) internal view returns (string memory) {
        string memory txs = _getGnosisHeader("1", L1_CONTRACT_CONTROLLER);

        string memory setLZConfigReceive = iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                L1_SYNC_POOL,
                L1_RECEIVE_302,
                LayerZeroHelpers.getDVNConfigWithBlockConfirmations(config.L2_EID, L1_DVN, 64)
            )
        );
        txs = string.concat(txs, _getGnosisTransaction(iToHex(abi.encodePacked(L1_ENDPOINT)), setLZConfigReceive, true));

        return txs;
    }

    function run() public {
        ConfigPerL2 storage config = getTargetChain();
        console.log("Target chain:", config.NAME);

        vm.startBroadcast();

        console.log("Deploying L1 contracts for", config.NAME);
        deployDummyToken(config);
        deployReceiver(config);

        vm.createDir("./output", true);

        string memory schedulePath = string.concat("./output/", config.NAME, "_L1_TimelockSchedule.json");
        string memory executePath = string.concat("./output/", config.NAME, "_L1_TimelockExecute.json");
        string memory configPath = string.concat("./output/", config.NAME, "_L1_ControllerConfig.json");

        vm.writeJson(getTimelockScheduleTransactions(config), schedulePath);
        vm.writeJson(getTimelockExecuteTransactions(config), executePath);
        vm.writeJson(getControllerConfigTransactions(config), configPath);

        vm.stopBroadcast();

        console.log("Simulating gnosis transaction bundles...");
        executeGnosisTransactionBundle(schedulePath, L1_TIMELOCK_GNOSIS);
        vm.warp(block.timestamp + 3 days);
        executeGnosisTransactionBundle(executePath, L1_TIMELOCK_GNOSIS);
        executeGnosisTransactionBundle(configPath, L1_CONTRACT_CONTROLLER);
        console.log("All transaction bundles simulated successfully");

    }
}
