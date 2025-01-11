// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LayerZeroHelpers} from "../../utils/LayerZeroHelpers.sol";
import {MockL1SyncPool} from "../../test/mock/MockL1SyncPool.sol";
import {L1HydraReceiverETHUpgradeable} from "../../contracts/NativeMinting/ReceiverContracts/L1HydraReceiverETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge script scripts/MockDeployment/DeployMockNativeMintingL1.s.sol:DeployMockNativeMintingL1 --rpc-url https://eth-sepolia.public.blastapi.io --via-ir --etherscan-api-key XZFNUB193BK4SD86U2NJXPB7HTRK2NNJ6J 
contract DeployMockNativeMintingL1 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        
        // sepolia address 
        address lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        address delegate = deployer;
        address l2syncPool = 0x861009a515D1083a89B426B70005E3Da99a9069b;
        uint32 l2eid = 40346;

        address mockPoolImpl = address(new MockL1SyncPool(lzEndpoint));
        address mockPool = address(new TransparentUpgradeableProxy(mockPoolImpl, delegate, ""));
        MockL1SyncPool(mockPool).initialize(delegate);

        address receiverImpl = address(new L1HydraReceiverETHUpgradeable());

        address receiver = address(new TransparentUpgradeableProxy(receiverImpl, delegate, ""));

        L1HydraReceiverETHUpgradeable(receiver).initialize(address(mockPool), lzEndpoint, deployer);

        // berachain secret testnet
        MockL1SyncPool(mockPool).setPeer(l2eid, LayerZeroHelpers._toBytes32(l2syncPool));
        MockL1SyncPool(mockPool).setReceiver(l2eid, address(receiver));

        
        vm.stopBroadcast();
    }
}
