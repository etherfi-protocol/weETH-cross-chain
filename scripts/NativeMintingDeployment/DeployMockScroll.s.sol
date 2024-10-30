// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../contracts/MintableOFTUpgradeable.sol";
import "../../contracts/EtherFiTimelock.sol";
import "../../utils/L2Constants.sol";

contract MockPriceOracle {

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (18446744073709551771, 1051440139080589421, block.timestamp, block.timestamp, 18446744073709551771);
    }

    function decimals() external view returns (uint256) {
        return 18;
    }
}

contract DeployOFTScript is Script, L2Constants {

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address scriptDeployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        address priceOracle = address(new MockPriceOracle());
        console.log("Deployed price oracle at: ", priceOracle);

        address oftImpl = address(new MintableOFTUpgradeable(SCROLL.L2_ENDPOINT));
        address oftProxy = address(
            new TransparentUpgradeableProxy(
                oftImpl,
                scriptDeployer,
                abi.encodeWithSelector(
                    MintableOFTUpgradeable.initialize.selector, "Scroll weETH", "weETH", scriptDeployer
                )
            )
        );
        console.log("L2 weeth deployed at", oftProxy);
    }

}
