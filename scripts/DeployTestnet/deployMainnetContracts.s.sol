// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";

contract mockEETH is ERC20 {
    constructor() ERC20("EtherFi ETH", "eETH") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}

contract mockWEETH is ERC20 {
    mockEETH public eeth;
    constructor(address _eeth) ERC20("Wrapped EtherFi ETH", "weETH") {
        eeth = mockEETH(_eeth);
    }

    function wrap(uint256 amount) public {
        _mint(msg.sender, amount);
        eeth.burn(msg.sender, amount);
    }
}

contract mockLiquifier {
    mockEETH public eeth;
    mockWEETH public weeth;

    constructor(address _eeth, address _weeth) {
        eeth = mockEETH(_eeth);
        weeth = mockWEETH(_weeth);
    }

    // mints our mock eeth to the recipient
    function depositWithERC20(address token, uint256 amount, address referral) public {
        if (token == address(eeth)) {
            eeth.mint(msg.sender, amount);
        } else {
            revert("Invalid token");
        }
    }
}

contract deployMainnetMock is Script, L2Constants {

    address constant sepoliaGnosis = 0x05b0f5a18AA3705dFf391f87c4BdD69eA6b8f80B;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        mockEETH eeth = new mockEETH();
        mockWEETH weeth = new mockWEETH(address(eeth));
        
        address[] memory controllers = new address[](1);
        controllers[0] = sepoliaGnosis;
        new EtherFiTimelock(1, new address[](0), new address[](0), sepoliaGnosis);




    }

}
