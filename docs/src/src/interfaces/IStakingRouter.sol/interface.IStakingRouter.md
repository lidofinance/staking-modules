# IStakingRouter
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IStakingRouter.sol)


## Functions
### DEFAULT_ADMIN_ROLE


```solidity
function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
```

### DEPOSIT_CONTRACT


```solidity
function DEPOSIT_CONTRACT() external view returns (address);
```

### FEE_PRECISION_POINTS


```solidity
function FEE_PRECISION_POINTS() external view returns (uint256);
```

### MANAGE_WITHDRAWAL_CREDENTIALS_ROLE


```solidity
function MANAGE_WITHDRAWAL_CREDENTIALS_ROLE() external view returns (bytes32);
```

### MAX_STAKING_MODULES_COUNT


```solidity
function MAX_STAKING_MODULES_COUNT() external view returns (uint256);
```

### MAX_STAKING_MODULE_NAME_LENGTH


```solidity
function MAX_STAKING_MODULE_NAME_LENGTH() external view returns (uint256);
```

### REPORT_EXITED_VALIDATORS_ROLE


```solidity
function REPORT_EXITED_VALIDATORS_ROLE() external view returns (bytes32);
```

### REPORT_REWARDS_MINTED_ROLE


```solidity
function REPORT_REWARDS_MINTED_ROLE() external view returns (bytes32);
```

### STAKING_MODULE_MANAGE_ROLE


```solidity
function STAKING_MODULE_MANAGE_ROLE() external view returns (bytes32);
```

### STAKING_MODULE_UNVETTING_ROLE


```solidity
function STAKING_MODULE_UNVETTING_ROLE() external view returns (bytes32);
```

### TOTAL_BASIS_POINTS


```solidity
function TOTAL_BASIS_POINTS() external view returns (uint256);
```

### UNSAFE_SET_EXITED_VALIDATORS_ROLE


```solidity
function UNSAFE_SET_EXITED_VALIDATORS_ROLE() external view returns (bytes32);
```

### addStakingModule


```solidity
function addStakingModule(
    string memory _name,
    address _stakingModuleAddress,
    uint256 _stakeShareLimit,
    uint256 _priorityExitShareThreshold,
    uint256 _stakingModuleFee,
    uint256 _treasuryFee,
    uint256 _maxDepositsPerBlock,
    uint256 _minDepositBlockDistance
) external;
```

### decreaseStakingModuleVettedKeysCountByNodeOperator


```solidity
function decreaseStakingModuleVettedKeysCountByNodeOperator(
    uint256 _stakingModuleId,
    bytes memory _nodeOperatorIds,
    bytes memory _vettedSigningKeysCounts
) external;
```

### canDeposit


```solidity
function canDeposit(uint256 _stakingModuleId) external view returns (bool);
```

### deposit


```solidity
function deposit(uint256 _stakingModuleId, bytes memory _depositCalldata) external payable;
```

### topUp


```solidity
function topUp(
    uint256 _stakingModuleId,
    uint256[] memory _keyIndices,
    uint256[] memory _operatorIds,
    bytes[] memory _pubkeys,
    uint256[] memory _topUpLimits
) external;
```

### finalizeUpgrade_v2


```solidity
function finalizeUpgrade_v2(uint256[] memory _priorityExitShareThresholds) external;
```

### getAllNodeOperatorDigests


```solidity
function getAllNodeOperatorDigests(uint256 _stakingModuleId) external view returns (NodeOperatorDigest[] memory);
```

### getAllStakingModuleDigests


```solidity
function getAllStakingModuleDigests() external view returns (StakingModuleDigest[] memory);
```

### getContractVersion


```solidity
function getContractVersion() external view returns (uint256);
```

### getDepositsAllocation


```solidity
function getDepositsAllocation(uint256 _depositsCount)
    external
    view
    returns (uint256 allocated, uint256[] memory allocations);
```

### getTopUpAllocation


```solidity
function getTopUpAllocation(uint256 _depositAmount)
    external
    view
    returns (uint256 allocated, uint256[] memory allocations);
```

### getLido


```solidity
function getLido() external view returns (address);
```

### getNodeOperatorDigests


```solidity
function getNodeOperatorDigests(uint256 _stakingModuleId, uint256[] memory _nodeOperatorIds)
    external
    view
    returns (NodeOperatorDigest[] memory digests);
```

### getNodeOperatorDigests


```solidity
function getNodeOperatorDigests(uint256 _stakingModuleId, uint256 _offset, uint256 _limit)
    external
    view
    returns (NodeOperatorDigest[] memory);
```

### getNodeOperatorSummary


```solidity
function getNodeOperatorSummary(uint256 _stakingModuleId, uint256 _nodeOperatorId)
    external
    view
    returns (NodeOperatorSummary memory summary);
```

### getRoleAdmin


```solidity
function getRoleAdmin(bytes32 role) external view returns (bytes32);
```

### getRoleMember


```solidity
function getRoleMember(bytes32 role, uint256 index) external view returns (address);
```

### getRoleMemberCount


```solidity
function getRoleMemberCount(bytes32 role) external view returns (uint256);
```

### getStakingFeeAggregateDistribution


```solidity
function getStakingFeeAggregateDistribution()
    external
    view
    returns (uint96 modulesFee, uint96 treasuryFee, uint256 basePrecision);
```

### getStakingFeeAggregateDistributionE4Precision


```solidity
function getStakingFeeAggregateDistributionE4Precision()
    external
    view
    returns (uint16 modulesFee, uint16 treasuryFee);
```

### getStakingModule


```solidity
function getStakingModule(uint256 _stakingModuleId) external view returns (StakingModule memory);
```

### getStakingModuleActiveValidatorsCount


```solidity
function getStakingModuleActiveValidatorsCount(uint256 _stakingModuleId)
    external
    view
    returns (uint256 activeValidatorsCount);
```

### getStakingModuleDigests


```solidity
function getStakingModuleDigests(uint256[] memory _stakingModuleIds)
    external
    view
    returns (StakingModuleDigest[] memory digests);
```

### getStakingModuleIds


```solidity
function getStakingModuleIds() external view returns (uint256[] memory stakingModuleIds);
```

### getStakingModuleIsActive


```solidity
function getStakingModuleIsActive(uint256 _stakingModuleId) external view returns (bool);
```

### getStakingModuleIsDepositsPaused


```solidity
function getStakingModuleIsDepositsPaused(uint256 _stakingModuleId) external view returns (bool);
```

### getStakingModuleIsStopped


```solidity
function getStakingModuleIsStopped(uint256 _stakingModuleId) external view returns (bool);
```

### getStakingModuleLastDepositBlock


```solidity
function getStakingModuleLastDepositBlock(uint256 _stakingModuleId) external view returns (uint256);
```

### getStakingModuleMaxDepositsCount


```solidity
function getStakingModuleMaxDepositsCount(uint256 _stakingModuleId, uint256 _maxDepositsValue)
    external
    view
    returns (uint256);
```

### getStakingModuleMaxDepositsPerBlock


```solidity
function getStakingModuleMaxDepositsPerBlock(uint256 _stakingModuleId) external view returns (uint256);
```

### getStakingModuleMinDepositBlockDistance


```solidity
function getStakingModuleMinDepositBlockDistance(uint256 _stakingModuleId) external view returns (uint256);
```

### getStakingModuleNonce


```solidity
function getStakingModuleNonce(uint256 _stakingModuleId) external view returns (uint256);
```

### getStakingModuleStatus


```solidity
function getStakingModuleStatus(uint256 _stakingModuleId) external view returns (uint8);
```

### getStakingModuleSummary


```solidity
function getStakingModuleSummary(uint256 _stakingModuleId)
    external
    view
    returns (StakingModuleSummary memory summary);
```

### getStakingModules


```solidity
function getStakingModules() external view returns (StakingModule[] memory res);
```

### getStakingModulesCount


```solidity
function getStakingModulesCount() external view returns (uint256);
```

### getStakingRewardsDistribution


```solidity
function getStakingRewardsDistribution()
    external
    view
    returns (
        address[] memory recipients,
        uint256[] memory stakingModuleIds,
        uint96[] memory stakingModuleFees,
        uint96 totalFee,
        uint256 precisionPoints
    );
```

### getTotalFeeE4Precision


```solidity
function getTotalFeeE4Precision() external view returns (uint16 totalFee);
```

### getWithdrawalCredentials


```solidity
function getWithdrawalCredentials() external view returns (bytes32);
```

### grantRole


```solidity
function grantRole(bytes32 role, address account) external;
```

### hasRole


```solidity
function hasRole(bytes32 role, address account) external view returns (bool);
```

### hasStakingModule


```solidity
function hasStakingModule(uint256 _stakingModuleId) external view returns (bool);
```

### initialize


```solidity
function initialize(address _admin, address _lido, bytes32 _withdrawalCredentials) external;
```

### onValidatorsCountsByNodeOperatorReportingFinished


```solidity
function onValidatorsCountsByNodeOperatorReportingFinished() external;
```

### renounceRole


```solidity
function renounceRole(bytes32 role, address account) external;
```

### reportRewardsMinted


```solidity
function reportRewardsMinted(uint256[] memory _stakingModuleIds, uint256[] memory _totalShares) external;
```

### reportValidatorExitDelay


```solidity
function reportValidatorExitDelay(
    uint256 _stakingModuleId,
    uint256 _nodeOperatorId,
    uint256 _proofSlotTimestamp,
    bytes calldata _publicKey,
    uint256 _eligibleToExitInSec
) external;
```

### reportStakingModuleExitedValidatorsCountByNodeOperator


```solidity
function reportStakingModuleExitedValidatorsCountByNodeOperator(
    uint256 _stakingModuleId,
    bytes memory _nodeOperatorIds,
    bytes memory _exitedValidatorsCounts
) external;
```

### reportStakingModuleOperatorBalances


```solidity
function reportStakingModuleOperatorBalances(
    uint256 _stakingModuleId,
    bytes memory _nodeOperatorIds,
    bytes memory _totalBalancesGwei
) external;
```

### reportStakingModuleStuckValidatorsCountByNodeOperator


```solidity
function reportStakingModuleStuckValidatorsCountByNodeOperator(
    uint256 _stakingModuleId,
    bytes memory _nodeOperatorIds,
    bytes memory _stuckValidatorsCounts
) external;
```

### revokeRole


```solidity
function revokeRole(bytes32 role, address account) external;
```

### setStakingModuleStatus


```solidity
function setStakingModuleStatus(uint256 _stakingModuleId, uint8 _status) external;
```

### setWithdrawalCredentials


```solidity
function setWithdrawalCredentials(bytes32 _withdrawalCredentials) external;
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool);
```

### unsafeSetExitedValidatorsCount


```solidity
function unsafeSetExitedValidatorsCount(
    uint256 _stakingModuleId,
    uint256 _nodeOperatorId,
    bool _triggerUpdateFinish,
    ValidatorsCountsCorrection memory _correction
) external;
```

### updateExitedValidatorsCountByStakingModule


```solidity
function updateExitedValidatorsCountByStakingModule(
    uint256[] memory _stakingModuleIds,
    uint256[] memory _exitedValidatorsCounts
) external returns (uint256);
```

### updateRefundedValidatorsCount


```solidity
function updateRefundedValidatorsCount(
    uint256 _stakingModuleId,
    uint256 _nodeOperatorId,
    uint256 _refundedValidatorsCount
) external;
```

### updateStakingModule


```solidity
function updateStakingModule(
    uint256 _stakingModuleId,
    uint256 _stakeShareLimit,
    uint256 _priorityExitShareThreshold,
    uint256 _stakingModuleFee,
    uint256 _treasuryFee,
    uint256 _maxDepositsPerBlock,
    uint256 _minDepositBlockDistance
) external;
```

### updateTargetValidatorsLimits


```solidity
function updateTargetValidatorsLimits(
    uint256 _stakingModuleId,
    uint256 _nodeOperatorId,
    uint256 _targetLimitMode,
    uint256 _targetLimit
) external;
```

### receive


```solidity
receive() external payable;
```

## Events
### ContractVersionSet

```solidity
event ContractVersionSet(uint256 version);
```

### ExitedAndStuckValidatorsCountsUpdateFailed

```solidity
event ExitedAndStuckValidatorsCountsUpdateFailed(uint256 indexed stakingModuleId, bytes lowLevelRevertData);
```

### RewardsMintedReportFailed

```solidity
event RewardsMintedReportFailed(uint256 indexed stakingModuleId, bytes lowLevelRevertData);
```

### RoleAdminChanged

```solidity
event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
```

### RoleGranted

```solidity
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
```

### RoleRevoked

```solidity
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
```

### StakingModuleAdded

```solidity
event StakingModuleAdded(uint256 indexed stakingModuleId, address stakingModule, string name, address createdBy);
```

### StakingModuleExitedValidatorsIncompleteReporting

```solidity
event StakingModuleExitedValidatorsIncompleteReporting(
    uint256 indexed stakingModuleId, uint256 unreportedExitedValidatorsCount
);
```

### StakingModuleFeesSet

```solidity
event StakingModuleFeesSet(
    uint256 indexed stakingModuleId, uint256 stakingModuleFee, uint256 treasuryFee, address setBy
);
```

### StakingModuleMaxDepositsPerBlockSet

```solidity
event StakingModuleMaxDepositsPerBlockSet(
    uint256 indexed stakingModuleId, uint256 maxDepositsPerBlock, address setBy
);
```

### StakingModuleMinDepositBlockDistanceSet

```solidity
event StakingModuleMinDepositBlockDistanceSet(
    uint256 indexed stakingModuleId, uint256 minDepositBlockDistance, address setBy
);
```

### StakingModuleShareLimitSet

```solidity
event StakingModuleShareLimitSet(
    uint256 indexed stakingModuleId, uint256 stakeShareLimit, uint256 priorityExitShareThreshold, address setBy
);
```

### StakingModuleStatusSet

```solidity
event StakingModuleStatusSet(uint256 indexed stakingModuleId, uint8 status, address setBy);
```

### StakingRouterETHDeposited

```solidity
event StakingRouterETHDeposited(uint256 indexed stakingModuleId, uint256 amount);
```

### WithdrawalCredentialsSet

```solidity
event WithdrawalCredentialsSet(bytes32 withdrawalCredentials, address setBy);
```

### WithdrawalsCredentialsChangeFailed

```solidity
event WithdrawalsCredentialsChangeFailed(uint256 indexed stakingModuleId, bytes lowLevelRevertData);
```

## Errors
### AppAuthLidoFailed

```solidity
error AppAuthLidoFailed();
```

### ArraysLengthMismatch

```solidity
error ArraysLengthMismatch(uint256 firstArrayLength, uint256 secondArrayLength);
```

### DepositContractZeroAddress

```solidity
error DepositContractZeroAddress();
```

### DirectETHTransfer

```solidity
error DirectETHTransfer();
```

### EmptyWithdrawalsCredentials

```solidity
error EmptyWithdrawalsCredentials();
```

### ExitedValidatorsCountCannotDecrease

```solidity
error ExitedValidatorsCountCannotDecrease();
```

### InvalidContractVersionIncrement

```solidity
error InvalidContractVersionIncrement();
```

### InvalidDepositsValue

```solidity
error InvalidDepositsValue(uint256 etherValue, uint256 depositsCount);
```

### InvalidMinDepositBlockDistance

```solidity
error InvalidMinDepositBlockDistance();
```

### InvalidPriorityExitShareThreshold

```solidity
error InvalidPriorityExitShareThreshold();
```

### InvalidPublicKeysBatchLength

```solidity
error InvalidPublicKeysBatchLength(uint256 actual, uint256 expected);
```

### InvalidReportData

```solidity
error InvalidReportData(uint256 code);
```

### InvalidSignaturesBatchLength

```solidity
error InvalidSignaturesBatchLength(uint256 actual, uint256 expected);
```

### NonZeroContractVersionOnInit

```solidity
error NonZeroContractVersionOnInit();
```

### ReportedExitedValidatorsExceedDeposited

```solidity
error ReportedExitedValidatorsExceedDeposited(
    uint256 reportedExitedValidatorsCount, uint256 depositedValidatorsCount
);
```

### StakingModuleAddressExists

```solidity
error StakingModuleAddressExists();
```

### StakingModuleNotActive

```solidity
error StakingModuleNotActive();
```

### StakingModuleStatusTheSame

```solidity
error StakingModuleStatusTheSame();
```

### StakingModuleUnregistered

```solidity
error StakingModuleUnregistered();
```

### StakingModuleWrongName

```solidity
error StakingModuleWrongName();
```

### StakingModulesLimitExceeded

```solidity
error StakingModulesLimitExceeded();
```

### UnexpectedContractVersion

```solidity
error UnexpectedContractVersion(uint256 expected, uint256 received);
```

### UnexpectedCurrentValidatorsCount

```solidity
error UnexpectedCurrentValidatorsCount(
    uint256 currentModuleExitedValidatorsCount,
    uint256 currentNodeOpExitedValidatorsCount,
    uint256 currentNodeOpStuckValidatorsCount
);
```

### UnrecoverableModuleError

```solidity
error UnrecoverableModuleError();
```

### ValueOver100Percent

```solidity
error ValueOver100Percent(string field);
```

### ZeroAddress

```solidity
error ZeroAddress(string field);
```

## Structs
### NodeOperatorSummary

```solidity
struct NodeOperatorSummary {
    uint256 targetLimitMode;
    uint256 targetValidatorsCount;
    uint256 stuckValidatorsCount;
    uint256 refundedValidatorsCount;
    uint256 stuckPenaltyEndTimestamp;
    uint256 totalExitedValidators;
    uint256 totalDepositedValidators;
    uint256 depositableValidatorsCount;
}
```

### NodeOperatorDigest

```solidity
struct NodeOperatorDigest {
    uint256 id;
    bool isActive;
    NodeOperatorSummary summary;
}
```

### StakingModule

```solidity
struct StakingModule {
    uint24 id;
    address stakingModuleAddress;
    uint16 stakingModuleFee;
    uint16 treasuryFee;
    uint16 stakeShareLimit;
    uint8 status;
    string name;
    uint64 lastDepositAt;
    uint256 lastDepositBlock;
    uint256 exitedValidatorsCount;
    uint16 priorityExitShareThreshold;
    uint64 maxDepositsPerBlock;
    uint64 minDepositBlockDistance;
}
```

### StakingModuleSummary

```solidity
struct StakingModuleSummary {
    uint256 totalExitedValidators;
    uint256 totalDepositedValidators;
    uint256 depositableValidatorsCount;
}
```

### StakingModuleDigest

```solidity
struct StakingModuleDigest {
    uint256 nodeOperatorsCount;
    uint256 activeNodeOperatorsCount;
    StakingModule state;
    StakingModuleSummary summary;
}
```

### ValidatorsCountsCorrection

```solidity
struct ValidatorsCountsCorrection {
    uint256 currentModuleExitedValidatorsCount;
    uint256 currentNodeOperatorExitedValidatorsCount;
    uint256 newModuleExitedValidatorsCount;
    uint256 newNodeOperatorExitedValidatorsCount;
}
```

## Enums
### StakingModuleStatus

```solidity
enum StakingModuleStatus {
    Active,
    DepositsPaused,
    Stopped
}
```

