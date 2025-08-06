// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/EtherFiTimelock.sol";
import "../interfaces/ICreate3Deployer.sol";
import "../utils/L2Constants.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


// forge script scripts/deployEtherFiTimelock.s.sol:DeployEtherFiTimelock --via-ir --ledger --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 --rpc-url "deployment rpc"
contract DeployEtherFiTimelock is Script, L2Constants {

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    function run() public {
        vm.startBroadcast();

        address[] memory controller = new address[](1);
        controller[0] = AVAX.L2_CONTRACT_CONTROLLER_SAFE;
        ProxyAdmin proxyAdmin = ProxyAdmin(AVAX.L2_OFT_PROXY_ADMIN);

        require(proxyAdmin.owner() == controller[0], "Proxy admin owner mismatch");

        bytes memory timelockCreationCode = abi.encodePacked(
            type(EtherFiTimelock).creationCode, 
            abi.encode(3 days, controller, controller, L2_TIMELOCK)
        );

        address timelockAddress = CREATE3.deployCreate3(keccak256("EtherFiTimelock"), timelockCreationCode);

        require(timelockAddress == L2_TIMELOCK, "Address mismatch");

        vm.stopBroadcast();
    }
}
