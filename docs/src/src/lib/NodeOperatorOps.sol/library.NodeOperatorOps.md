# NodeOperatorOps
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/NodeOperatorOps.sol)

The library is used to reduce BaseModule bytecode size.


## Functions
### createNodeOperator


```solidity
function createNodeOperator(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address from,
    NodeOperatorManagementProperties calldata managementProperties
) external;
```

### setTargetLimit


```solidity
function setTargetLimit(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    uint256 targetLimitMode,
    uint256 targetLimit
) external;
```

### updateExitedValidatorsCount


```solidity
function updateExitedValidatorsCount(
    ModuleLinearStorage.BaseModuleStorage storage $,
    bytes calldata nodeOperatorIds,
    bytes calldata exitedValidatorsCounts
) external;
```

### unsafeUpdateValidatorsCount


```solidity
function unsafeUpdateValidatorsCount(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 exitedValidatorsCount
) external;
```

### decreaseVettedSigningKeysCount


```solidity
function decreaseVettedSigningKeysCount(
    ModuleLinearStorage.BaseModuleStorage storage $,
    bytes calldata nodeOperatorIds,
    bytes calldata vettedSigningKeysCounts
) external;
```

### reportValidatorBalance


```solidity
function reportValidatorBalance(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 keyIndex,
    uint256 currentBalanceWei
) external;
```

### increaseKeyAddedBalancesByAllocations


```solidity
function increaseKeyAddedBalancesByAllocations(
    mapping(uint256 => uint256) storage keyAddedBalances,
    uint256[] calldata operatorIds,
    uint256[] calldata keyIndices,
    uint256[] calldata allocations
) external;
```

### removeKeys


```solidity
function removeKeys(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    uint256 startIndex,
    uint256 keysCount,
    bool useKeyRemovalCharge
) external;
```

### addKeys


```solidity
function addKeys(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures
) external;
```

### calculateDepositableValidatorsCount


```solidity
function calculateDepositableValidatorsCount(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId
) external view returns (uint256 newCount);
```

### getNodeOperatorSummary


```solidity
function getNodeOperatorSummary(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    IAccounting accounting
)
    external
    view
    returns (
        uint256 targetLimitMode,
        uint256 targetValidatorsCount,
        uint256 stuckValidatorsCount,
        uint256 refundedValidatorsCount,
        uint256 stuckPenaltyEndTimestamp,
        uint256 totalExitedValidators,
        uint256 totalDepositedValidators,
        uint256 depositableValidatorsCount
    );
```

### capTopUpLimitsByKeyBalance


```solidity
function capTopUpLimitsByKeyBalance(
    mapping(uint256 => uint256) storage keyAddedBalances,
    uint256[] calldata operatorIds,
    uint256[] calldata keyIndices,
    uint256[] calldata topUpLimits
) external view returns (uint256[] memory cappedTopUpLimits);
```

### getNodeOperatorIds


```solidity
function getNodeOperatorIds(uint256 nodeOperatorsCount, uint256 offset, uint256 limit)
    external
    pure
    returns (uint256[] memory nodeOperatorIds);
```

### distributeTopUpAllocations

Distribute per-operator allocations to per-key allocations with per-key limits.


```solidity
function distributeTopUpAllocations(
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits,
    uint256[] calldata allocatedOperatorIds,
    uint256[] calldata operatorAllocations,
    uint256 operatorsCount
) external pure returns (uint256[] memory allocations, uint256[] memory perOperatorIncrements);
```

### _increaseKeyAddedBalance


```solidity
function _increaseKeyAddedBalance(
    mapping(uint256 => uint256) storage keyAddedBalances,
    uint256 nodeOperatorId,
    uint256 keyIndex,
    uint256 incrementWei
) internal;
```

### _updateExitedValidatorsCount


```solidity
function _updateExitedValidatorsCount(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 exitedValidatorsCount,
    bool allowDecrease
) internal;
```

### _onlyExistingNodeOperator


```solidity
function _onlyExistingNodeOperator(uint256 nodeOperatorId, uint256 nodeOperatorsCount) internal pure;
```

### _keyAddedBalanceCap


```solidity
function _keyAddedBalanceCap() private pure returns (uint256);
```

