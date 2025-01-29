// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockMintableToken} from "../../test/mock/MockMintToken.sol";
import {LayerZeroHelpers} from "../../utils/LayerZeroHelpers.sol";
import {MockExchangeRateProvider} from "../../test/mock/MockExchangeRateProvider.sol";
import {HydraSyncPoolETHUpgradeable} from "../../contracts/native-minting/L2SyncPoolContracts/HydraSyncPoolETHUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

// forge script scripts/MockDeployment/DeployMockNativeMintingL2.s.sol:DeployMockNativeMintingL2 --rpc-url https://rockbeard-eth-cartio.berachain.com  --via-ir
contract DeployMockNativeMintingL2 is Script {
    using OptionsBuilder for bytes;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        
        vm.startBroadcast(deployerPrivateKey);

        address endpoint = 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff;
        address berawETH = 0x2d93FbcE4CffC15DD385A80B3f4CC1D4E76C38b3;
        address stargateOFTETH = 0x4F5F42799d1E01662B629Ede265baEa223e9f9C7;
        address l1Receiver = 0xE8C337A39601BC8DAf241E50A829dF109B82Fd56;
        address l1syncPool = 0xBb03aAbA47BBE950fF1C263F61651543839d9f2a;
        uint32 l1Eid = 40161;

        MockMintableToken token = new MockMintableToken("Mock weETH", "weETH");
        MockExchangeRateProvider rateProvider = new MockExchangeRateProvider();

        address poolImpl = address(new HydraSyncPoolETHUpgradeable(
            endpoint,
            berawETH
        ));

        HydraSyncPoolETHUpgradeable poolProxy = HydraSyncPoolETHUpgradeable(address(new TransparentUpgradeableProxy(poolImpl, deployer, "")));

        poolProxy.initialize(address(rateProvider), address(0x0), address(token), l1Eid, stargateOFTETH, l1Receiver, deployer);

        poolProxy.setPeer(l1Eid, LayerZeroHelpers._toBytes32(l1syncPool));

        IOAppOptionsType3(address(poolProxy)).setEnforcedOptions(getEnforcedOptions(l1Eid));

        poolProxy.setL1TokenIn(berawETH, Constants.ETH_ADDRESS);

        IERC20(berawETH).approve(address(poolProxy), type(uint256).max);

        poolProxy.deposit(berawETH, 0.1 ether, 0.09 ether);

        (MessagingFee memory standardFee, uint256 fee) = poolProxy.quoteSyncTotal(berawETH, hex"", false);

        poolProxy.sync{value: fee}(berawETH, hex"", standardFee);

        vm.stopBroadcast();
    }

    function getEnforcedOptions(uint32 _eid) public pure returns (EnforcedOptionParam[] memory) {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);

        enforcedOptions[0] = EnforcedOptionParam({
            eid: _eid,
            msgType: 0,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: _eid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });
        enforcedOptions[2] = EnforcedOptionParam({
            eid: _eid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });

        return enforcedOptions; 
    }
}
