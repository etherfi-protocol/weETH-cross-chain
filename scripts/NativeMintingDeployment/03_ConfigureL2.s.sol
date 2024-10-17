// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../contracts/NativeMinting/L2SyncPoolContracts/L2ScrollSyncPoolETHUpgradeable.sol";
import "../../utils/L2Constants.sol";
import "../../utils/GnosisHelpers.sol";


contract L2NativeMintingScript is Script, L2Constants, GnosisHelpers {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /*//////////////////////////////////////////////////////////////
                            Deployment Config
    //////////////////////////////////////////////////////////////*/

    address constant L2_SYNC_POOL = L1_CONTRACT_CONTROLLER;
    address constant L1_RECEIVER = L1_ENDPOINT;

    /*//////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////*/
    

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        L2ScrollSyncPoolETHUpgradeable syncPool = L2ScrollSyncPoolETHUpgradeable(L2_SYNC_POOL);
        syncPool.setReceiver(L1_RECEIVER);
        syncPool.transferOwnership(SCROLL.L2_CONTRACT_CONTROLLER_SAFE);

        string memory minterTransaction = _getGnosisHeader(SCROLL.CHAIN_ID);

        bytes memory setMinterData = abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ROLE, L2_SYNC_POOL);
        minterTransaction = string.concat(minterTransaction, _getGnosisTransaction(iToHex(abi.encodePacked(SCROLL.L2_OFT)), iToHex(setMinterData), true));

        vm.writeJson(minterTransaction, "./output/setMinter.json");
    }
}
