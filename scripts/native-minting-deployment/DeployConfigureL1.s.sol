// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/native-minting/receivers/L1HydraReceiverETHUpgradeable.sol";
import "../../contracts/native-minting/DummyTokenUpgradeable.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";
import {CREATE3} from "solmate/src/utils/CREATE3.sol";

// forge script scripts/native-minting-deployment/DeployConfigureL1.s.sol:L1NativeMintingScript --evm-version "paris" --via-ir --rpc-url "https://mainnet.gateway.tenderly.co" --ledger --verify --etherscan-api-key "etherscan key"
contract L1NativeMintingScript is Script, L2Constants, GnosisHelpers {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // address constant 
    address constant STARGATE_POOL_NATIVE = 0x77b2043768d28E9C9aB44E1aBfC95944bcE57931;
    
    function run() public {
        
        // vm.startBroadcast(DEPLOYER_ADDRESS);
        vm.startPrank(DEPLOYER_ADDRESS);

        console.log("Deploying contracts on L1...");
        
        address dummyTokenImpl = address(new DummyTokenUpgradeable{salt: keccak256("BeraTokenImpl")}(18));
        address dummyTokenProxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("BeraDummyToken")}(
                dummyTokenImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    DummyTokenUpgradeable.initialize.selector, "Bera Dummy ETH", "beraETH", DEPLOYER_ADDRESS
                )
            )
        );
        console.log("DummyToken deployed at: ", dummyTokenProxy);
        require(dummyTokenProxy == BERA.L1_DUMMY_TOKEN, "Dummy Token address mismatch");

        DummyTokenUpgradeable dummyToken = DummyTokenUpgradeable(dummyTokenProxy);
        dummyToken.grantRole(MINTER_ROLE, L1_SYNC_POOL);
        dummyToken.grantRole(DEFAULT_ADMIN_ROLE, L1_CONTRACT_CONTROLLER);
        dummyToken.renounceRole(DEFAULT_ADMIN_ROLE, DEPLOYER_ADDRESS);

        address beraReceiverImpl = address(new L1HydraReceiverETHUpgradeable{salt: keccak256("ReceiverImpl")}(STARGATE_POOL_NATIVE));
        address beraReceiverProxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("Receiver")}(
                beraReceiverImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    L1HydraReceiverETHUpgradeable.initialize.selector, L1_SYNC_POOL, BERA.L1_MESSENGER, L1_CONTRACT_CONTROLLER
                )
            )
        );
        console.log("BeraReceiver deployed at: ", beraReceiverProxy);
        require(beraReceiverProxy == BERA.L1_RECEIVER, "BeraReceiver address mismatch");
        
        console.log("Generating L1 transactions for native minting...");

        // the require transactions to integrate native minting on the L1 side are spilt between the timelock and the L1 contract controller
        
        // 1. generate the schedule and execute transactions for the L1 sync pool
        string memory timelock_schedule_transactions = _getGnosisHeader("1");
        string memory timelock_execute_transactions = _getGnosisHeader("1");
        
        // registers the new dummy token as an acceptable token for the vamp contract
        bytes memory setTokenData = abi.encodeWithSignature("registerToken(address,address,bool,uint16,uint32,uint32,bool)", BERA.L1_DUMMY_TOKEN, address(0), true, 0, 20_000, 200_000, true); 
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_VAMP, setTokenData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_VAMP, setTokenData, false));

        // set {receiver, dummy} token on the L1 sync pool
        bytes memory setReceiverData = abi.encodeWithSignature("setReceiver(uint32,address)", BERA.L2_EID, BERA.L1_RECEIVER);
        bytes memory setDummyTokenData = abi.encodeWithSignature("setDummyToken(uint32,address)", BERA.L2_EID, BERA.L1_DUMMY_TOKEN);
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setDummyTokenData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setDummyTokenData, false));

        // set OFT peer to bera L2 sync pool that require the timelock for the L1 sync pool
        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", BERA.L2_EID, LayerZeroHelpers._toBytes32(BERA.L2_SYNC_POOL));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setPeerData, true));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setPeerData, true));

        vm.writeJson(timelock_schedule_transactions, "./output/L1NativeMintingScheduleTransactions.json");
        vm.writeJson(timelock_execute_transactions, "./output/L1NativeMintingExecuteTransactions.json");

        // 2. generate transactions required by the L1 contract controller
        string memory l1_contract_controller_transaction = _getGnosisHeader("1");

        // set DVN receive config for the L1 sync to receive messages from the L2 sync pool
        string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_SYNC_POOL, L1_RECEIVE_302, LayerZeroHelpers.getDVNConfig(BERA.L2_EID, L1_DVN)));
        l1_contract_controller_transaction = string.concat(l1_contract_controller_transaction, _getGnosisTransaction(iToHex(abi.encodePacked(L1_ENDPOINT)), setLZConfigReceive, true));

        vm.writeJson(l1_contract_controller_transaction, "./output/L1NativeMintingSetConfig.json");
    }
}
