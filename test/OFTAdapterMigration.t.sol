// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { EtherFiOFTAdapterUpgradeable } from "../contracts/EtherFIOFTAdapterUpgrabeable.sol";
import { EtherFiOFTAdapter } from "../contracts/EtherFIOFTAdapter.sol";
import "../utils/Constants.sol";
import "../utils/LayerZeroHelpers.sol";
import "../contracts/MintableOFTUpgradeable.sol";

import "../node_modules/layerzero-v2/oapp/contracts/oft/interfaces/IOFT.sol";

import "forge-std/Test.sol";

contract OFTAdapterMigration is Test, Constants, LayerZeroHelpers {
    
    function test_AdapterMigration () public {
        vm.createSelectFork("https://mainnet.gateway.tenderly.co");
        EtherFiOFTAdapter adapter = EtherFiOFTAdapter(L1_OFT_ADAPTER);
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        vm.startPrank(deployer);

        // deploying the new upgradeable adapter 
        address adapterImpl = address(new EtherFiOFTAdapterUpgradeable(L1_WEETH, L1_ENDPOINT));
        address adapterUpgradeableAddress = address(new TransparentUpgradeableProxy(adapterImpl, deployer,
            abi.encodeWithSelector(
                EtherFiOFTAdapterUpgradeable.initialize.selector, L1_CONTRACT_CONTROLLER, L1_CONTRACT_CONTROLLER
            )
        ));
        EtherFiOFTAdapterUpgradeable adapterUpgradeable = EtherFiOFTAdapterUpgradeable(adapterUpgradeableAddress);

        // deploying the OFT that sends the migration messages
        address migrationOFTImpl = address(new MintableOFTUpgradeable(L1_ENDPOINT));
        address migrationOFTAddress = address(
            new TransparentUpgradeableProxy(
                migrationOFTImpl,
                deployer,
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, deployer
                )
            )
        );

        // giving the deployer permission to mint migration tokens 
        MintableOFTUpgradeable migrationOFT = MintableOFTUpgradeable(migrationOFTAddress);
        migrationOFT.setPeer(L1_EID, _toBytes32(adapterUpgradeableAddress));
        bytes32 minter_role = migrationOFT.MINTER_ROLE();
        migrationOFT.grantRole(minter_role, deployer);

        // minting the migration tokens
        migrationOFT.mint(deployer, 100 ether);

        vm.stopPrank();
        vm.startPrank(L1_CONTRACT_CONTROLLER);

        adapter.setPeer(L1_EID, _toBytes32(migrationOFTAddress));

        vm.stopPrank();
        vm.startPrank(deployer);

        SendParam memory param = SendParam({
            dstEid: L1_EID,
            to: _toBytes32(deployer),
            amountLD: 5600000000000,
            minAmountLD: 5000000000000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        }); 

        migrationOFT.quoteSend(param, false);

    }
}