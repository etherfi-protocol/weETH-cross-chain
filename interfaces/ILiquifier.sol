// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquifier {
    struct DeprecatedStruct_QueuedWithdrawal {
        address strategies;
        uint256[] shares;
        address staker;
        DeprecatedStruct_WithdrawerAndNonce withdrawerAndNonce;
        uint32 withdrawalStartBlock;
        address delegatedAddress;
    }

    struct DeprecatedStruct_WithdrawerAndNonce {
        address withdrawer;
        uint96 nonce;
    }

    struct PermitInput {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        address strategies;
        uint256[] shares;
    }

    error AlreadyRegistered();
    error EthTransferFailed();
    error IncorrectCaller();
    error NotEnoughBalance();
    error NotRegistered();
    error NotSupportedToken();
    error StrategyShareNotEnough();
    error WrongOutput();

    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event CompletedQueuedWithdrawal(bytes32 _withdrawalRoot);
    event CompletedStEthQueuedWithdrawals(uint256[] _reqIds);
    event Initialized(uint8 version);
    event Liquified(address _user, uint256 _toEEthAmount, address _fromToken, bool _isRestaked);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event QueuedStEthWithdrawals(uint256[] _reqIds);
    event RegisteredQueuedWithdrawal(bytes32 _withdrawalRoot, DeprecatedStruct_QueuedWithdrawal _queuedWithdrawal);
    event RegisteredQueuedWithdrawal_V2(bytes32 _withdrawalRoot, Withdrawal _queuedWithdrawal);
    event Unpaused(address account);
    event Upgraded(address indexed implementation);

    function CASE1() external;
    function DEPRECATED_accumulatedFee() external view returns (uint128);
    function DEPRECATED_eigenLayerWithdrawalClaimGasCost() external view returns (uint32);
    function DEPRECATED_quoteStEthWithCurve() external view returns (bool);
    function admins(address) external view returns (bool);
    function cbEth() external view returns (address);
    function cbEth_Eth_Pool() external view returns (address);
    function completeQueuedWithdrawals(
        Withdrawal[] memory _queuedWithdrawals,
        address _tokens,
        uint256[] memory _middlewareTimesIndexes
    ) external;
    function depositWithERC20(address _token, uint256 _amount, address _referral) external returns (uint256);
    function depositWithERC20WithPermit(address _token, uint256 _amount, address _referral, PermitInput memory _permit)
        external
        returns (uint256);
    function depositWithQueuedWithdrawal(Withdrawal memory _queuedWithdrawal, address _referral)
        external
        returns (uint256);
    function dummies(uint256) external view returns (address);
    function eigenLayerDelegationManager() external view returns (address);
    function eigenLayerStrategyManager() external view returns (address);
    function getImplementation() external view returns (address);
    function getTotalPooledEther(address _token) external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256 total);
    function getTotalPooledEtherSplits(address _token)
        external
        view
        returns (uint256 restaked, uint256 holding, uint256 pendingForWithdrawals);
    function initialize(
        address _treasury,
        address _liquidityPool,
        address _eigenLayerStrategyManager,
        address _lidoWithdrawalQueue,
        address _stEth,
        address _cbEth,
        address _wbEth,
        address _cbEth_Eth_Pool,
        address _wbEth_Eth_Pool,
        address _stEth_Eth_Pool,
        uint32 _timeBoundCapRefreshInterval
    ) external;
    function initializeL1SyncPool(address _l1SyncPool) external;
    function initializeOnUpgrade(address _eigenLayerDelegationManager, address _pancakeRouter) external;
    function isDepositCapReached(address _token, uint256 _amount) external view returns (bool);
    function isL2Eth(address _token) external view returns (bool);
    function isRegisteredQueuedWithdrawals(bytes32) external view returns (bool);
    function isTokenWhitelisted(address _token) external view returns (bool);
    function l1SyncPool() external view returns (address);
    function lido() external view returns (address);
    function lidoWithdrawalQueue() external view returns (address);
    function liquidityPool() external view returns (address);
    function owner() external view returns (address);
    function pancakeSwapForEth(
        address _token,
        uint256 _amount,
        uint24 _fee,
        uint256 _minOutputAmount,
        uint256 _maxWaitingTime
    ) external;
    function pauseContract() external;
    function pauseDeposits(address _token) external;
    function paused() external view returns (bool);
    function proxiableUUID() external view returns (bytes32);
    function quoteByFairValue(address _token, uint256 _amount) external view returns (uint256);
    function quoteByMarketValue(address _token, uint256 _amount) external view returns (uint256);
    function quoteStrategyShareForDeposit(address _token, address _strategy, uint256 _share)
        external
        view
        returns (uint256);
    function registerToken(
        address _token,
        address _target,
        bool _isWhitelisted,
        uint16 _discountInBasisPoints,
        uint32 _timeBoundCapInEther,
        uint32 _totalCapInEther,
        bool _isL2Eth
    ) external;
    function renounceOwnership() external;
    function stEthClaimWithdrawals(uint256[] memory _requestIds, uint256[] memory _hints) external;
    function stEthRequestWithdrawal(uint256 _amount) external returns (uint256[] memory);
    function stEthRequestWithdrawal() external returns (uint256[] memory);
    function stEth_Eth_Pool() external view returns (address);
    function swapCbEthToEth(uint256 _amount, uint256 _minOutputAmount) external returns (uint256);
    function swapStEthToEth(uint256 _amount, uint256 _minOutputAmount) external returns (uint256);
    function swapWbEthToEth(uint256 _amount, uint256 _minOutputAmount) external returns (uint256);
    function timeBoundCap(address _token) external view returns (uint256);
    function timeBoundCapRefreshInterval() external view returns (uint32);
    function tokenInfos(address)
        external
        view
        returns (
            uint128 strategyShare,
            uint128 ethAmountPendingForWithdrawals,
            address strategy,
            bool isWhitelisted,
            uint16 discountInBasisPoints,
            uint32 timeBoundCapClockStartTime,
            uint32 timeBoundCapInEther,
            uint32 totalCapInEther,
            uint96 totalDepositedThisPeriod,
            uint96 totalDeposited,
            bool isL2Eth
        );
    function totalCap(address _token) external view returns (uint256);
    function totalDeposited(address _token) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function treasury() external view returns (address);
    function unPauseContract() external;
    function unwrapL2Eth(address _l2Eth) external payable returns (uint256);
    function updateAdmin(address _address, bool _isAdmin) external;
    function updateDepositCap(address _token, uint32 _timeBoundCapInEther, uint32 _totalCapInEther) external;
    function updateTimeBoundCapRefreshInterval(uint32 _timeBoundCapRefreshInterval) external;
    function updateWhitelistedToken(address _token, bool _isWhitelisted) external;
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
    function verifyQueuedWithdrawal(address _user, Withdrawal memory _queuedWithdrawal)
        external
        view
        returns (bytes32);
    function wbEth() external view returns (address);
    function wbEth_Eth_Pool() external view returns (address);
    function withdrawEther() external;
}
