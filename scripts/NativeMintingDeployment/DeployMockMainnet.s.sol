// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/NativeMinting/EtherfiL1SyncPoolETH.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";

import "../../contracts/NativeMinting/mockEETH.sol";
import "../../contracts/NativeMinting/mockWEETH.sol";
import "../../contracts/NativeMinting/mockLiquifier.sol";

contract deployMainnetMock is Script, L2Constants {

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        address eeth = new mockEETH;
        console.log("Deployed mockEETH at: ", address(eeth));
        mockWEETH weeth = new mockWEETH(address(eeth));
        console.log("Deployed mockWEETH at: ", address(weeth));

        mockLiquifier liquifier = new mockLiquifier(address(eeth), address(weeth));
        console.log("Deployed mockLiquifier at: ", address(liquifier));
        
        address[] memory controllers = new address[](1);
        controllers[0] = L1_TIMELOCK_GNOSIS;
        address timelock = address(new EtherFiTimelock(1, controllers, controllers, L1_TIMELOCK_GNOSIS));
        console.log("Deployed timelock at: ", timelock);

        address l1syncpoolImpl = address(new EtherfiL1SyncPoolETH(L1_ENDPOINT));
        EtherfiL1SyncPoolETH l1syncpool = EtherfiL1SyncPoolETH(address(
            new TransparentUpgradeableProxy(
                address(l1syncpoolImpl),
                L1_CONTRACT_CONTROLLER,
                ""
            ))
        );
        console.log("Deployed L1SyncPool at: ", address(l1syncpool));

        l1syncpool.initialize(address(liquifier), address(eeth), address(weeth), L1_OFT_ADAPTER, address(timelock));

    }

}
