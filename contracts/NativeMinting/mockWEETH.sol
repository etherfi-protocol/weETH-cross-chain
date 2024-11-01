pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./mockEETH.sol";

contract mockWEETH is ERC20 {
    mockEETH public eeth;
    constructor(address _eeth) ERC20("Wrapped EtherFi ETH", "weETH") {
        eeth = mockEETH(_eeth);
    }

    function wrap(uint256 amount) public returns (uint256) {
        uint256 weETHToMint = (amount * 95) / 100;
        _mint(msg.sender, weETHToMint);
        eeth.transferFrom(msg.sender, address(this), amount);

        return weETHToMint;
    }
}
