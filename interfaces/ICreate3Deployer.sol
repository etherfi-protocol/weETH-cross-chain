interface ICreate3Deployer {
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function deployCreate3(bytes memory initCode) external payable returns (address);
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    ) external payable returns (address);
}
