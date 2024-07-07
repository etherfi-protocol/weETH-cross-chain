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

contract CrossChainSend is Script, Constants {


    function run() public {
        address scriptDeployer;
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);


        /*//////////////////////////////////////////////////////////////
                         Current Send Parameters
        //////////////////////////////////////////////////////////////*/
        
        // Initializing the sending OFT (only set if sending from L2)
        IOFT SENDING_OFT = IOFT(address(0));

        // Desintation EID
        uint32 DST_EID = 30184;

        /*//////////////////////////////////////////////////////////////
                    
        //////////////////////////////////////////////////////////////*/

        // If sending from L1, the OFT adapter is the OFT
        if (block.chainid != 1) {
            SENDING_OFT = IOFT(L1_OFT_ADAPTER);
        }

    
        // Define the SendParam struct
        SendParam memory param = SendParam({
            dstEid: DST_EID,
            to: 0x000000000000000000000000C83bb94779c5577AF1D48dF8e2A113dFf0cB127c,
            amountLD: 5600000000000,
            minAmountLD: 5000000000000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = SENDING_OFT.quoteSend(param, false);

        try SENDING_OFT.send{value: fee.nativeFee }(
            param, 
            fee,
            0xC83bb94779c5577AF1D48dF8e2A113dFf0cB127c
        ) {
            console.log("Success");
        } catch Error(string memory reason) {
            console.log("Error: ", reason);
        } catch (bytes memory lowLevelData) {
            console.logBytes(lowLevelData);
        }
    }
}