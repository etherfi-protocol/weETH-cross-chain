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

        mockLiquifier liquifier = new mockLiquifier(0x67EB7914BB065d4Ed9D5507A4D60dEFE0589A5e1, 0xcAD5310CF56E54442F47b79BdCecFd3B2940A783);
        console.log("Deployed mockLiquifier at: ", address(liquifier));

    }

}
