# NodeOperatorOps
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/NodeOperatorOps.sol)

External deployment-linked library used by BaseModule-compatible modules
to reduce bytecode size.


## Functions
### createNodeOperator


```solidity
function createNodeOperator(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address from,
    NodeOperatorManagementProperties calldata managementProperties,
    address stETH
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
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256[] calldata operatorIds,
    uint256[] calldata keyIndices,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory cappedTopUpLimits);
```

### getKeyAllocatedBalances


```solidity
function getKeyAllocatedBalances(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 startIndex,
    uint256 keysCount
) external view returns (uint256[] memory balances);
```

### getKeyConfirmedBalances


```solidity
function getKeyConfirmedBalances(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 startIndex,
    uint256 keysCount
) external view returns (uint256[] memory balances);
```

### getNodeOperatorIds


```solidity
function getNodeOperatorIds(uint256 nodeOperatorsCount, uint256 offset, uint256 limit)
    external
    pure
    returns (uint256[] memory nodeOperatorIds);
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

### _keyBalanceCap


```solidity
function _keyBalanceCap() private pure returns (uint256);
```

