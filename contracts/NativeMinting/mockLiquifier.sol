pragma solidity ^0.8.24;
import "./mockEETH.sol";
import "./mockWEETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract mockLiquifier {
    mockEETH public eeth;
    mockWEETH public weeth;

    constructor(address _eeth, address _weeth) {
        eeth = mockEETH(_eeth);
        weeth = mockWEETH(_weeth);
    }

    // mints our mock eeth to the recipient
    function depositWithERC20(address token, uint256 amount, address referral) public {

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        eeth.mint(msg.sender, amount);
    }

    function unwrapL2Eth(address dummyToken) public payable {
        IERC20(dummyToken).transfer(msg.sender, msg.value);
    }
}
