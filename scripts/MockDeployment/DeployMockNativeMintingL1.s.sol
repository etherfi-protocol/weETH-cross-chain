// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Script} from "forge-std/Script.sol";
import {LayerZeroHelpers} from "../../utils/LayerZeroHelpers.sol";
import {MockL1SyncPool} from "../../test/mock/MockL1SyncPool.sol";
import {L1HydraReceiverETHUpgradeable} from "../../contracts/NativeMinting/ReceiverContracts/L1HydraReceiverETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge script scripts/MockDeployment/DeployMockNativeMintingL1.s.sol:DeployMockNativeMintingL1 --rpc-url https://eth-sepolia.public.blastapi.io --via-ir
contract DeployMockNativeMintingL1 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        
        // sepolia address 
        address lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        address delegate = deployer;
        address l2syncPool = 0x97A81E9AE7051243912E6ACff860C92c9B12657D;
        address stargatePoolNative = 0x9Cc7e185162Aa5D1425ee924D97a87A0a34A0706;
        
        uint32 l2eid = 40346;

        address mockPoolImpl = address(new MockL1SyncPool(lzEndpoint));
        address mockPool = address(new TransparentUpgradeableProxy(mockPoolImpl, delegate, ""));
        MockL1SyncPool(mockPool).initialize(delegate);

        address receiverImpl = address(new L1HydraReceiverETHUpgradeable(stargatePoolNative));

        address receiver = address(new TransparentUpgradeableProxy(receiverImpl, delegate, ""));

        L1HydraReceiverETHUpgradeable(payable(receiver)).initialize(address(mockPool), lzEndpoint, deployer);

        // berachain secret testnet
        MockL1SyncPool(mockPool).setPeer(l2eid, LayerZeroHelpers._toBytes32(l2syncPool));
        MockL1SyncPool(mockPool).setReceiver(l2eid, address(receiver));

        vm.stopBroadcast();
    }
}
