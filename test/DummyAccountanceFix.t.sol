// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/DummyTokenUpgradeable.sol";
import "../utils/Constants.sol";

import "forge-std/Test.sol";

contract DummyAccountanceFix is Test, Constants {

    // deployed with upgradeDummyTokenImpl
    address public newDummyTokenImpl = 0xA6a93Ac26ba057CD1f12b3Be92c80A1009a86089;

    // https://lineascan.build/tx/0xfe0eb5fcbcf294b58c42a5da0ea74b2b6ee3c336c879c2fa731c0fb978349cad
    // 1,425.840649412019898121 ETH
    uint256 public dummyTokenInbound1 = 1425840649412019898121;
    // https://lineascan.build/tx/0x8a97c7accaf44b05e18f5bc5ab6eec0bdc4daab99c7bd466e43a0554ed7102f0
    // 1,003.344822695284422 ETH
    uint256 public dummyTokenInbound2 = 1003344822695284422000;
    // https://lineascan.build/tx/0xbdffa78876293317bfddae3b0042f17e30e981ac8a474ea919547df70556c294
    // 1,086.076011329824003747 ETH
    uint256 public dummyTokenInbound3 = 1086076011329824003747;

    function testFix() public {
        uint256 totalAmountSwap = dummyTokenInbound1 + dummyTokenInbound2 + dummyTokenInbound3;
        DummyTokenUpgradeable blastDummyToken = DummyTokenUpgradeable(BLAST.L1_DUMMY_TOKEN);
        DummyTokenUpgradeable lineaDummyToken = DummyTokenUpgradeable(LINEA.L1_DUMMY_TOKEN);
        ProxyAdmin lineaDummyTokenProxyAdmin = ProxyAdmin(LINEA.L1_DUMMY_TOKEN_PROXY_ADMIN);

        vm.createSelectFork(L1_RPC_URL);

        // setting the chain to the state expected after failed `slowSync` transactions are executed
        vm.prank(L1_SYNC_POOL_ADDRESS);
        lineaDummyToken.mint(L1_VAMPIRE, totalAmountSwap);

        uint256 blastSupplyBefore = blastDummyToken.totalSupply();
        uint256 lineaSupplyBefore = lineaDummyToken.totalSupply();
        console.log("blastSupplyBefore", blastSupplyBefore);
        console.log("lineaSupplyBefore", lineaSupplyBefore);

        // Currently the owner of the dummy token address is the deployer NEED TO CHANGE TO L1_CONTRACT_CONTROLLER
        vm.prank(0xf8a86ea1Ac39EC529814c377Bd484387D395421e);
        lineaDummyTokenProxyAdmin.transferOwnership(L1_CONTRACT_CONTROLLER);

        vm.startPrank(L1_CONTRACT_CONTROLLER);

        // grant minter role to L1_CONTRACT_CONTROLLER
        blastDummyToken.grantRole(blastDummyToken.MINTER_ROLE(), L1_CONTRACT_CONTROLLER);

        // mint the burnt blast tokens
        blastDummyToken.mint(L1_CONTRACT_CONTROLLER, totalAmountSwap);

        // upgrade to the linea dummy token to the burnable version
        lineaDummyTokenProxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(LINEA.L1_DUMMY_TOKEN), newDummyTokenImpl, "");
        vm.stopPrank();

        // burn the surplus linea tokens 
        vm.prank(0xf8a86ea1Ac39EC529814c377Bd484387D395421e); // NEED TO CHANGE TO L1_CONTRACT_CONTROLLER
        lineaDummyToken.burnFrom(L1_VAMPIRE, totalAmountSwap);

        uint256 blastSupplyAfter = blastDummyToken.totalSupply();
        uint256 lineaSupplyAfter = lineaDummyToken.totalSupply();
        console.log("blastSupplyAfter", blastSupplyAfter);
        console.log("lineaSupplyAfter", lineaSupplyAfter);

        assertEq(blastSupplyBefore + lineaSupplyBefore, blastSupplyAfter + lineaSupplyAfter);
    }
}
