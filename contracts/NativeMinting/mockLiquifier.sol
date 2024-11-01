pragma solidity ^0.8.24;
import "./mockEETH.sol";
import "./mockWEETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMockLiquifier {
    function unwrapL2Eth(address _l2Eth) external payable returns (uint256);
    function depositWithERC20(address _token, uint256 _amount, address _referral) external returns (uint256);
}

contract mockLiquifier is IMockLiquifier {
    mockEETH public eeth;
    mockWEETH public weeth;

    constructor(address _eeth, address _weeth) {
        eeth = mockEETH(_eeth);
        weeth = mockWEETH(_weeth);
    }

    // mints our mock eeth to the recipient
    function depositWithERC20(address token, uint256 amount, address referral) public returns (uint256) {

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        eeth.mint(msg.sender, amount);
        return amount;
    }

    function unwrapL2Eth(address dummyToken) public payable returns (uint256) {
        IERC20(dummyToken).transfer(msg.sender, msg.value);

        return msg.value;
    }
}
