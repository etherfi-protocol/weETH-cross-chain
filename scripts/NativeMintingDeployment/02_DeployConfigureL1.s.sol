// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/NativeMinting/ReceiverContracts/L1ScrollReceiverETHUpgradeable.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract L1NativeMintingScript is Script, L2Constants, LayerZeroHelpers, GnosisHelpers {

    /*//////////////////////////////////////////////////////////////
                            Deployment Config
    //////////////////////////////////////////////////////////////*/

    string constant DUMMY_TOKEN_NAME = "Scroll Dummy ETH";
    string constant DUMMY_TOKEN_SYMBOL = "scrollETH";
    address constant L1_MESSENGER = 0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367;

    address constant L2_SYNC_POOL = address(0);

    /*//////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////*/
    
    function run() public {

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        console.log("Deploying contracts on L1...");
        
        address dummyTokenImpl = address(new DummyTokenUpgradeable(18));
        address dummyTokenProxy = address(
            new TransparentUpgradeableProxy(
                dummyTokenImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    DummyTokenUpgradeable.initialize.selector, DUMMY_TOKEN_NAME, DUMMY_TOKEN_SYMBOL, scriptDeployer
                )
            )
        );
        console.log("DummyToken deployed at: ", dummyTokenProxy);

        address scrollReceiverImpl = address(new L1ScrollReceiverETHUpgradeable());
        address scrollReceiverProxy = address(
            new TransparentUpgradeableProxy(
                scrollReceiverImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    L1ScrollReceiverETHUpgradeable.initialize.selector, L1_SYNC_POOL, L1_MESSENGER, L1_CONTRACT_CONTROLLER
                )
            )
        );
        console.log("ScrollReceiver deployed at: ", scrollReceiverProxy);

        // set LayerZero configure for L2 sync pool to communicate with the L1 sync pool (L1 sync pool via timelock)

        console.log("Generating L1 transactions for native minting...");
    
        string memory timelock_schedule_transactions = _getGnosisHeader("1");
        string memory timelock_execute_transactions = _getGnosisHeader("1");
    
        // register dummy token on liquifier
        bytes memory setTokenData = abi.encodeWithSignature("registerToken(address,address,bool,uint16,uint32,uint32,bool)", dummyTokenProxy, address(0), true, 0, 20_000, 200_000, true); 

        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_VAMP, setTokenData, false));
        timelock_schedule_transactions = string.concat(timelock_execute_transactions, _getGnosisScheduleTransaction(L1_VAMP, setTokenData, false));

        // set receiver and dummy token on the L1 sync pool
        bytes memory setReceiverData = abi.encodeWithSignature("setReceiver(uint32,address)", SCROLL.L2_EID, scrollReceiverProxy);
        bytes memory setDummyTokenData = abi.encodeWithSignature("setTokenOut(uint32,address)", SCROLL.L2_EID, dummyTokenProxy);

        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setDummyTokenData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setDummyTokenData, false));

        // set all of the OFT configurations for the L1 sync pool
        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", SCROLL.L2_EID, _toBytes32(L2_SYNC_POOL));
        bytes memory setEnforcedOptionsData = abi.encodeWithSignature("setEnforcedOptions((uint32,uint16,bytes)[])", getEnforcedOptions(SCROLL.L2_EID));
        bytes memory setLZConfigReceive = abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_SYNC_POOL, L1_SEND_302, getDVNConfig(SCROLL.L2_EID, L1_DVN));

        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setPeerData, false));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setEnforcedOptionsData, false));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_ENDPOINT, setLZConfigReceive, true));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setPeerData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setEnforcedOptionsData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_ENDPOINT, setLZConfigReceive, true));

        vm.writeJson(timelock_schedule_transactions, "./output/L1NativeMintingScheduleTransactions.json");
        vm.writeJson(timelock_execute_transactions, "./output/L1NativeMintingExecuteTransactions.json");
    }
}
