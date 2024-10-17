// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";

contract mockEETH is ERC20 {
    constructor() ERC20("EtherFi ETH", "eETH") {
        _mint(msg.sender, 1000000000000000000000000000);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract mockWEETH {

}

contract mockLiquifier {
    mockEETH public eeth;
    mockWEETH public weeth;

    constructor(address _eeth, address _weeth) {
        eeth = mockEETH(_eeth);
        weeth = mockWEETH(_weeth);
    }

    function depositWithERC20(address token, uint256 amount, address referral) public {
        
    }

}

contract DeployOFTScript is Script, L2Constants {

    address constant sepoliaGnosis = 0x05b0f5a18AA3705dFf391f87c4BdD69eA6b8f80B;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        address[] memory controllers = new address[](1);
        controllers[0] = sepoliaGnosis;
        new EtherFiTimelock(1, new address[](0), new address[](0), sepoliaGnosis);




    }

}
