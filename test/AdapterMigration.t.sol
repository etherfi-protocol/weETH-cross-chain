// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../scripts/AdapterMigration/01_DeployUpgradeableAdapter.s.sol" as DeployOFTAdapter;
import "../scripts/AdapterMigration/02_DeployMigrationOFT.s.sol" as DeployMigrationOFT;

import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../contracts/MigrationOFT.sol";
import "../contracts/EtherFiOFTAdapter.sol";    
import "../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../contracts/MintableOFTUpgradeable.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

// allows us to interface with the delegates map that isn't defined in the ILayerZeroEndpointV2 inteface
interface EndpointDelegates {
    function delegates(address) external view returns (address);
}

contract OFTMigrationUnitTests is Test, Constants, LayerZeroHelpers {
    
    // Send a migration message on arbitrum and ensures access control is enforced
    function test_MigrationSend() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        MigrationOFT migrationOFT = MigrationOFT(DEPLOYMENT_OFT);

        // ensure that the arb gnosis has sufficient funds for cross chain send
        startHoax(DEPLOYMENT_CONTRACT_CONTROLLER);

        uint256 fee = migrationOFT.quoteMigrationMessage(10 ether);
        migrationOFT.sendMigrationMessage{value: fee}(10 ether);

        fee = migrationOFT.quoteMigrationMessage(70000 ether);
        migrationOFT.sendMigrationMessage{value: fee}(70000 ether);

        address alice = vm.addr(1);
        startHoax(alice);

        fee = migrationOFT.quoteMigrationMessage(10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );

        migrationOFT.sendMigrationMessage{value: fee}(10 ether);
    }

    function test_VerifyMigrationOFTDelegate() public {
         vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        MigrationOFT migrationOFT = MigrationOFT(DEPLOYMENT_OFT);
        EndpointDelegates endpoint = EndpointDelegates(DEPLOYMENT_LZ_ENDPOINT);

        address migrationOFTDelegate = endpoint.delegates(address(migrationOFT));

        assertEq(migrationOFTDelegate, DEPLOYMENT_CONTRACT_CONTROLLER);
    }

    function test_MigrationOFTReceive() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        MigrationOFT migrationOFT = MigrationOFT(DEPLOYMENT_OFT);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(DEPLOYMENT_LZ_ENDPOINT);

        endpoint.getConfig(address(migrationOFT), DEPLOYMENT_RECEIVE_LIB_302, L1_EID, 2);
        endpoint.getConfig(address(migrationOFT), DEPLOYMENT_SEND_LID_302, L1_EID, 2);

        assertEq(endpoint.getConfig(address(migrationOFT), DEPLOYMENT_SEND_LID_302, L1_EID, 2), _getExpectedUln(DEPLOYMENT_LZ_DVN, DEPLOYMENT_NETHERMIND_DVN));
        assertEq(endpoint.getConfig(address(migrationOFT), DEPLOYMENT_RECEIVE_LIB_302, L1_EID, 2), _getDeadUln());
    }
    
    // Deplooys new upgradeable adapter and sends cross chain messages to all L2s
    function test_UpgradeableOFTAdapter() public {
        vm.createSelectFork(L1_RPC_URL);

        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(L1_ENDPOINT);
        EtherfiOFTAdapterUpgradeable adapter = EtherfiOFTAdapterUpgradeable(DEPLOYMENT_OFT_ADAPTER);

        for (uint256 i = 0; i < L2s.length; i++) {
            // ensuring outbound transfers execute successfully
            _sendCrossChain(L2s[i].L2_EID, DEPLOYMENT_OFT_ADAPTER,  1 ether, false);

            // confirm all configuration variables for this L2
            assertTrue(adapter.isPeer(L2s[i].L2_EID, _toBytes32(L2s[i].L2_OFT)));
            assertEq(adapter.enforcedOptions(L2s[i].L2_EID, 1), hex"000301001101000000000000000000000000000f4240");
            assertEq(adapter.enforcedOptions(L2s[i].L2_EID, 2), hex"000301001101000000000000000000000000000f4240");
            assertEq(endpoint.getConfig(DEPLOYMENT_OFT_ADAPTER, L1_SEND_302, L2s[i].L2_EID, 2), _getExpectedUln(L1_LZ_DVN, L1_NETHERMIND_DVN));
            assertEq(endpoint.getConfig(DEPLOYMENT_OFT_ADAPTER, L1_RECEIVE_302, L2s[i].L2_EID, 2), _getExpectedUln(L1_LZ_DVN, L1_NETHERMIND_DVN));
        }

    }

    // Verify the expected configurations after the migration is complete
    function test_VerifyMainnetMigrationConfig() public {
        vm.createSelectFork(L1_RPC_URL);
        EtherFiOFTAdapter adapter = EtherFiOFTAdapter(L1_OFT_ADAPTER);
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(L1_ENDPOINT);

        executeGnosisTransactionBundle("./transactions/01_migrationSetup/connnect-migration-peer.json", L1_CONTRACT_CONTROLLER);

        // Assert that the adapter is properly configured
        assertTrue(adapter.isPeer(DEPLOYMENT_EID, _toBytes32(DEPLOYMENT_OFT)));
        assertEq(adapter.enforcedOptions(DEPLOYMENT_EID, 1), hex"000301001101000000000000000000000000000f4240");
        assertEq(adapter.enforcedOptions(DEPLOYMENT_EID, 2), hex"000301001101000000000000000000000000000f4240");

        // Assert that the endpoint is properly configured to __receive__ messages from the migration peer
        assertEq(endpoint.getConfig(L1_OFT_ADAPTER, L1_RECEIVE_302, DEPLOYMENT_EID, 2), _getExpectedUln(L1_DVN[0], L1_DVN[1]));

        _sendCrossChain(DEPLOYMENT_EID, L1_OFT_ADAPTER, 1 ether, true);
    }

    // Simulates execution of the pausing/unpausing cross-chain messages on each chain
    function test_PauseCrossChain() public {
        // execute mainnet transaction
        vm.createSelectFork(L1_RPC_URL);

        executeGnosisTransactionBundle("./transactions/02_pauseCrossChain/disconnect-mainnet.json", L1_CONTRACT_CONTROLLER);
        
        // all L1 -> L2 messages should fail
        for (uint256 i = 0; i < L2s.length; i++) {
            _sendCrossChain(L2s[i].L2_EID, L1_OFT_ADAPTER, 1 ether, true);
        }

        // execute all L2 transactions
        for (uint256 i = 0; i < L2s.length; i++) {
            if (keccak256(abi.encodePacked(L2s[i].NAME)) == keccak256(abi.encodePacked("zksync"))) {
                // can't test zksync on a forge fork due to the different execution environment
                continue;
            }
            vm.createSelectFork(L2s[i].RPC_URL);
            executeGnosisTransactionBundle(string.concat("./transactions/02_pauseCrossChain/disconnect-", L2s[i].NAME, ".json"), L2s[i].L2_CONTRACT_CONTROLLER_SAFE);

            // transfers to all target pairs should fail 
            for (uint256 j = 0; j < L2s.length; j++) {
                if (i == j) { 
                    // skip send to self chain, test L2 -> mainnet here instead
                    _sendCrossChain(L1_EID, L2s[i].L2_OFT, 0.01 ether, true);
                    continue;
                }
                _sendCrossChain(L2s[j].L2_EID, L2s[i].L2_OFT, 0.01 ether, true);
            }

            // // Reconnect the chains, connect to new Adapter test that the transfers are successful
            executeGnosisTransactionBundle(string.concat("./transactions/03_unpauseCrossChain/reconnect-", L2s[i].NAME, ".json"), L2s[i].L2_CONTRACT_CONTROLLER_SAFE);
            for (uint256 j = 0; j < L2s.length; j++) {
                 if (i == j) {
                    // skip send to self chain, test L2 -> mainnet here instead
                    _sendCrossChain(L1_EID, L2s[i].L2_OFT, 0.01 ether, false);
                    // assert that the new adapter has been set as the peer
                    assertTrue(MintableOFTUpgradeable(L2s[i].L2_OFT).isPeer(L1_EID, _toBytes32(DEPLOYMENT_OFT_ADAPTER)));
                    continue;
                }
                _sendCrossChain(L2s[j].L2_EID, L2s[i].L2_OFT, 0.01 ether, false);
                
            }
        }
    }

    function test_SetProxyAdmin() public {
        vm.createSelectFork(L1_RPC_URL);

        // ADMIN_SLOT, specified by EIP1967, that stores the proxy admin address
        address proxyAdminAddress = address(uint160(uint256(vm.load(DEPLOYMENT_OFT_ADAPTER, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))));
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        assert(proxyAdmin.owner() == L1_TIMELOCK);
    }

    /**
     * @dev Simulations the execution of a gnosis transaction bundle on the current fork
     * @param transactionPath The path to the transaction bundle json file
     * @param sender The address of the gnosis safe that will execute the transaction
     */
    function executeGnosisTransactionBundle(string memory transactionPath, address sender) public {
        string memory json = vm.readFile(transactionPath);
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", Strings.toString(i), "]")); i++) {
            address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].to"));
            uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].data"));

            vm.prank(sender);
            (bool success,) = address(to).call{value: value}(data);
            require(success, "Transaction failed");
        }
    }

    // A helper function to send weETH cross chain
    function _sendCrossChain(uint32 dstEid, address sourceOft, uint256 amount, bool expectRevert) public {
        address weETH = sourceOft;
        if (block.chainid == 1) { 
            weETH = L1_WEETH;
        }
        address sender = vm.addr(1);
        vm.deal(sender, 100 ether);
        deal(address(weETH), address(sender), amount);

        vm.prank(sender);
        IERC20(weETH).approve(sourceOft, amount);

        SendParam memory param = SendParam({
            dstEid: dstEid,
            to: _toBytes32(sender),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });

        OFT oftInterface = OFT(sourceOft);
        MessagingFee memory fee;
        
        if (expectRevert) {
            vm.expectRevert();
            fee = oftInterface.quoteSend(param, false);

            fee = MessagingFee({
                nativeFee: 1 ether,
                lzTokenFee: 0
            });
        } else {
            fee = oftInterface.quoteSend(param, false);
        }

        if (expectRevert) {
            vm.expectRevert();
        }
        vm.prank(sender);
        oftInterface.send{value: fee.nativeFee}(
            param,
            fee,
            sender
        );
    }

}
