// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../contracts/NativeMinting/ReceiverContracts/L1ScrollReceiverETHUpgradeable.sol";
import "../../contracts/NativeMinting/DummyTokenUpgradeable.sol";
import "../../utils/GnosisHelpers.sol";
import "../../utils/L2Constants.sol";
import "../../utils/LayerZeroHelpers.sol";



contract L1NativeMintingScript is Script, L2Constants, LayerZeroHelpers, GnosisHelpers {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    function run() public {
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        IL1ScrollMessenger messenger = IL1ScrollMessenger(SCROLL.L1_MESSENGER);

        IL1ScrollMessenger.L2MessageProof memory proof =  IL1ScrollMessenger.L2MessageProof({
            batchIndex: 82117,
            merkleProof: hex"000000000000000000000000000000000000000000000000000000000000000012f8048b9603d4478fa954058b3d0a1399bd170ffe6bf0a0178ccd8afca4c666b4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d303b4d090f9d4b45470512fa9bfb283062016fa3e55593e7bf4bceef78f75770507c7e752f983d0acb80518aac74d061eb76e97b049aae0af5e6589797c2c56da670c72a613954f6e589710d718be213a10fc39ef18264a7ff3efb5396481f291c6327471c06a458f894408a502594aa3dec830b592b22f0be2bc5dea5b494453affd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f839867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756afcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0e7ac046f3dbec80ffd4b3c3b047859f54cd6ba4782f7e9eb53def3f24d9f8b9c6765e02c28aa26019943ce68bdbc35e0ff61b0c3c8f2d1f94c31479a87749e5825a5f8a1d4fa8b333112f400d5ab224c972b5c86a03ffa0c84d78bde2180932bc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8beccd98dc6e569c87f338c68fa23139bafe238eb1308610d4a9b148fc1955128d4ce7874b09783cef2e7750f7ea24f6090c9ce47f33cf25ca5e16a1207b4a50fda2be1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a1ef973d30ca636d922d10ae577c73bc4fe92699225f30c0c2e9d6727bceb256d"
        });

        messenger.relayMessageWithProof(
            0xECB657Fa9aDeCD372022D13a52d39CCC193C6f17,
            0x155DA067E62224052EcF41a5197C1C98304D25C6,
            10000000000000000,
            367738,
            hex"3a69197e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000009ceaeeceaa3d038e560b692af44ec1131137b7c8341b878c5fb6ff2018c2ce758794000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000021c9fd8526d597",
            proof
            );

        console.log("Deploying contracts on L1...");
        
        address dummyTokenImpl = address(new DummyTokenUpgradeable{salt: keccak256("ScrollDummyTokenImplMock2")}(18));
        address dummyTokenProxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("ScrollDummyTokenMock2")}(
                dummyTokenImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    DummyTokenUpgradeable.initialize.selector, "Scroll Dummy ETH", "scrollETH", DEPLOYER_ADDRESS
                )
            )
        );
        console.log("DummyToken deployed at: ", dummyTokenProxy);
        require(dummyTokenProxy == SCROLL.L1_DUMMY_TOKEN, "Dummy Token address mismatch");

        DummyTokenUpgradeable dummyToken = DummyTokenUpgradeable(dummyTokenProxy);
        dummyToken.grantRole(MINTER_ROLE, L1_SYNC_POOL);
        dummyToken.grantRole(DEFAULT_ADMIN_ROLE, L1_CONTRACT_CONTROLLER);
        dummyToken.renounceRole(DEFAULT_ADMIN_ROLE, DEPLOYER_ADDRESS);

        address scrollReceiverImpl = address(new L1ScrollReceiverETHUpgradeable{salt: keccak256("ScrollReceiverImplMock2")}());
        address scrollReceiverProxy = address(
            new TransparentUpgradeableProxy{salt: keccak256("ScrollReceiverMock2")}(
                scrollReceiverImpl, 
                L1_TIMELOCK, 
                abi.encodeWithSelector(
                    L1ScrollReceiverETHUpgradeable.initialize.selector, L1_SYNC_POOL, SCROLL.L1_MESSENGER, L1_CONTRACT_CONTROLLER
                )
            )
        );
        console.log("ScrollReceiver deployed at: ", scrollReceiverProxy);
        require(scrollReceiverProxy == SCROLL.L1_RECEIVER, "ScrollReceiver address mismatch");
        vm.stopPrank();
        
        console.log("Generating L1 transactions for native minting...");

        // the require transactions to integrate native minting on the L1 side are spilt between the timelock and the L1 contract controller
        
        // 1. generate the schedule and execute transactions for the L1 sync pool
        string memory timelock_schedule_transactions = _getGnosisHeader("11155111");
        string memory timelock_execute_transactions = _getGnosisHeader("11155111");
        
        // registers the new dummy token as an acceptable token for the vamp contract
        // no need on testnet the mock vamp contract doesn't have a whitelist
        // bytes memory setTokenData = abi.encodeWithSignature("registerToken(address,address,bool,uint16,uint32,uint32,bool)", dummyTokenProxy, address(0), true, 0, 20_000, 200_000, true); 
        // timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_VAMP, setTokenData, false));
        // timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_VAMP, setTokenData, false));

        set {receiver, dummy} token on the L1 sync pool
        bytes memory setReceiverData = abi.encodeWithSignature("setReceiver(uint32,address)", SCROLL.L2_EID, scrollReceiverProxy);
        bytes memory setDummyTokenData = abi.encodeWithSignature("setDummyToken(uint32,address)", SCROLL.L2_EID, dummyTokenProxy);
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setDummyTokenData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setReceiverData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setDummyTokenData, false));

        // set OFT peer to scroll L2 sync pool that require the timelock for the L1 sync pool
        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", SCROLL.L2_EID, _toBytes32(SCROLL.L2_SYNC_POOL));
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setPeerData, false));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setPeerData, false));

        // TODO: remove this transaction after the scroll native minting upgrade. It is a one time call to transfer the LZ delegate for the L1 sync pool from the deployer EOA to the L1 contract controller
        bytes memory setDelegate = abi.encodeWithSignature("setDelegate(address)", L1_CONTRACT_CONTROLLER);
        timelock_schedule_transactions = string.concat(timelock_schedule_transactions, _getGnosisScheduleTransaction(L1_SYNC_POOL, setDelegate, true));
        timelock_execute_transactions = string.concat(timelock_execute_transactions, _getGnosisExecuteTransaction(L1_SYNC_POOL, setDelegate, true));

        vm.writeJson(timelock_schedule_transactions, "./output/L1NativeMintingScheduleTransactions.json");
        vm.writeJson(timelock_execute_transactions, "./output/L1NativeMintingExecuteTransactions.json");

        // 2. generate transactions required by the L1 contract controller
        string memory l1_contract_controller_transaction = _getGnosisHeader("11155111");

        // set DVN receive config for the L1 sync to receive messages from the L2 sync pool
        string memory setLZConfigReceive = iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", L1_SYNC_POOL, L1_RECEIVE_302, getDVNConfig(SCROLL.L2_EID, L1_DVN)));
        l1_contract_controller_transaction = string.concat(l1_contract_controller_transaction, _getGnosisTransaction(iToHex(abi.encodePacked(L1_ENDPOINT)), setLZConfigReceive, true));

        vm.writeJson(l1_contract_controller_transaction, "./output/L1NativeMintingSetConfig.json");
    }
}
