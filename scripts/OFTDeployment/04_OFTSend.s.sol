// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import "forge-std/Script.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "forge-std/Test.sol";
import "../../utils/Constants.sol";
import "../../utils/LayerZeroHelpers.sol";

contract CrossChainSend is Script, Constants, LayerZeroHelpers {


    function run() public {
        // script deployer is both the sender and the recipient of this cross-chain send
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        /*//////////////////////////////////////////////////////////////
                         Current Send Parameters
        //////////////////////////////////////////////////////////////*/
        
        // Initializing the sending OFT (only set if sending from L2)
        IOFT SENDING_OFT = IOFT(0xCA8dF0B6bD5588f3FD651F85f6E5aCe325bA9Dfd);
        IERC20 SENDING_ERC20 = IERC20(0xCA8dF0B6bD5588f3FD651F85f6E5aCe325bA9Dfd);

        // Desintation EID
        uint32 DST_EID = 30101;

        /*//////////////////////////////////////////////////////////////
                    
        //////////////////////////////////////////////////////////////*/

        // If sending from L1, the OFT adapter is the OFT
        if (block.chainid == 1) {
            SENDING_OFT = IOFT(0xEa95431608E72058E4e06742DDacd789c76543c8);
            SENDING_ERC20 = IERC20(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
        }
    
        // Define the SendParam struct (script deployer is the recipient)
        SendParam memory param = SendParam({
            dstEid: DST_EID,
            to: _toBytes32(scriptDeployer),
            amountLD: 5300,
            minAmountLD: 5000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = SENDING_OFT.quoteSend(param, false);
        SENDING_ERC20.approve(address(SENDING_OFT), 5300);

        try SENDING_OFT.send{value: fee.nativeFee }(
            param, 
            fee,
            scriptDeployer
        ) {
            console.log("Success");
        } catch Error(string memory reason) {
            console.log("Error: ", reason);
        } catch (bytes memory lowLevelData) {
            console.logBytes(lowLevelData);
        }
    }
}
