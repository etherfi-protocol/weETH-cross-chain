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

import "../../contracts/EtherfiOFTUpgradeable.sol";
import "forge-std/Test.sol";
import "../../utils/L2Constants.sol";

// forge script scripts/oft-deployment/05_OFTSend.s.sol:CrossChainSend --rpc-url "source chain" --private-key "dev wallet"
contract CrossChainSend is Script, L2Constants {

    function run() public {
        // script deployer is both the sender and the recipient of this cross-chain send
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        /*//////////////////////////////////////////////////////////////
                         Current Send Parameters
        //////////////////////////////////////////////////////////////*/
        
        // Initializing the sending OFT (only set if sending from L2)
        IOFT SENDING_OFT = IOFT(0x7DCC39B4d1C53CB31e1aBc0e358b43987FEF80f7);
        IERC20 SENDING_ERC20 = IERC20(address(SENDING_OFT));

        // Desintation EID
        uint32 DST_EID = 30101;

        /*//////////////////////////////////////////////////////////////
                    
        //////////////////////////////////////////////////////////////*/

        // If sending from L1, the OFT adapter is the OFT
        if (block.chainid == 1) {
            SENDING_OFT = IOFT(L1_OFT_ADAPTER);
            SENDING_ERC20 = IERC20(L1_WEETH);
        }
    
        // Define the SendParam struct (script deployer is the recipient)
        SendParam memory param = SendParam({
            dstEid: DST_EID,
            to: _toBytes32(scriptDeployer),
            amountLD: 50000000000000,
            minAmountLD: 50000000000000,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = SENDING_OFT.quoteSend(param, false);
        SENDING_ERC20.approve(address(SENDING_OFT), 50000000000000);

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

    function _toBytes32(address addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
