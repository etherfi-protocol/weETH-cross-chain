// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import "../../contracts/MintableOFTUpgradeable.sol";
import "../../contracts/EtherfiOFTAdapterUpgradeable.sol";
import "../../utils/LiquidAssetsConstants.sol";
import "../../utils/LayerZeroHelpers.sol";


// Deploys and configures an OFT on scroll for a liquid asset
contract DeployOFT is Script, LiquidConstants, LayerZeroHelpers {
    using OptionsBuilder for bytes;
    
    address oftProxy;
    RateLimiter.RateLimitConfig[] public rateLimitConfigs;
    EnforcedOptionParam[] public enforcedOptions;

    /*//////////////////////////////////////////////////////////////
                    Current Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    address constant DEPLOYMENT_OFT_ADAPTER = address(0x0);
    string constant TOKEN_NAME = WEETHS_NAME;
    string constant TOKEN_SYMBOL = WEETHS_SYMBOL;

    /*//////////////////////////////////////////////////////////////
                
    //////////////////////////////////////////////////////////////*/

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        // Create salt for deployment
        bytes32 SALT = keccak256(abi.encodePacked(scriptDeployer, TOKEN_NAME));

        address oftImpl = address(new MintableOFTUpgradeable{salt: SALT}(SCROLL_LZ_ENDPOINT));
        oftProxy  = address(
            new TransparentUpgradeableProxy{salt: SALT}(
                oftImpl,
                SCROLL_CONTRACT_CONTROLLER,
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL, scriptDeployer
                )
            )
        );

        console.log("Deployed OFT at address: ", oftProxy);

        MintableOFTUpgradeable oft = MintableOFTUpgradeable(oftProxy);

        console.log("Setting configs...");

        oft.setPeer(L1_EID, _toBytes32(DEPLOYMENT_OFT_ADAPTER));

        _setDVN(SCROLL_DVN[0], SCROLL_DVN[1]);
        _appendEnforcedOptions(L1_EID);
        oft.setEnforcedOptions(enforcedOptions);

        // same as weETH for weETHs, but 80 bitcoins for eBTC to account for the higher value
        // 8_000_000_000 satoshis = 80 bitcoins
        rateLimitConfigs.push(_getRateLimitConfig(L1_EID, 2000 ether, 4 hours));
        oft.setRateLimits(rateLimitConfigs);

        console.log("Transaferring permissions...");

        // setting the contract controller as the delegate
        oft.setDelegate(SCROLL_CONTRACT_CONTROLLER);

        // set the contract controller as the default admin
        oft.grantRole(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000), SCROLL_CONTRACT_CONTROLLER);

        // revoke the script deployer's admin role
        oft.renounceRole(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000), scriptDeployer);
        
        // transfer ownership to the contract controller
        oft.transferOwnership(SCROLL_CONTRACT_CONTROLLER);
        

        vm.stopBroadcast();
    }

    // Configures the deployment chain's DVN for the given destination chain
    function _setDVN(address lzDvn, address nethermindDvn) internal {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);

        // The DVN arrays are sorted in ascending order (enforced by requires statements in the layerzer endpoint contract)
        if (lzDvn > nethermindDvn) {
            requiredDVNs[0] = nethermindDvn;
            requiredDVNs[1] = lzDvn;
        } else {
            requiredDVNs[0] = lzDvn;
            requiredDVNs[1] = nethermindDvn;
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(L1_EID, 2, abi.encode(ulnConfig));

        ILayerZeroEndpointV2(SCROLL_LZ_ENDPOINT).setConfig(oftProxy, SCROLL_SEND_302, params);
        ILayerZeroEndpointV2(SCROLL_LZ_ENDPOINT).setConfig(oftProxy, SCROLL_RECEIVE_302, params);
    }

    function _appendEnforcedOptions(uint32 dstEid) internal {
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        }));
    }

}
