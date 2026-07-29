# StakeTracker
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/StakeTracker.sol)

Centralizes tracked stake updates for operator extra balances, total extra stake, and key balance transitions.
External deployment-linked library used by BaseModule-compatible modules.


## Functions
### increaseOperatorBalance

Increases tracked operator extra balance and total extra stake by the given delta.


```solidity
function increaseOperatorBalance(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 operatorId,
    uint256 incrementWei
) internal;
```

### decreaseOperatorBalance

Decreases tracked operator extra balance and total extra stake by the given delta.


```solidity
function decreaseOperatorBalance(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 operatorId,
    uint256 decrementWei
) internal;
```

### increaseKeyBalances

Applies per-key top-up allocations, updates key allocated balances, and aggregates stake deltas per operator.


```solidity
function increaseKeyBalances(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256[] calldata operatorIds,
    uint256[] calldata keyIndices,
    uint256[] calldata allocations
) external;
```

### getOperatorBalance

Returns the total tracked stake for the given operator: base 32 ETH per active validator plus stored extra.


```solidity
function getOperatorBalance(ModuleLinearStorage.BaseModuleStorage storage $, uint256 operatorId)
    internal
    view
    returns (uint256);
```

### getTotalModuleStake

Returns the total tracked module stake: base 32 ETH per active validator plus stored extra.


```solidity
function getTotalModuleStake(ModuleLinearStorage.BaseModuleStorage storage $) internal view returns (uint256);
```

### reportValidatorBalance

Raises confirmed key balance and also raises allocated balance when the confirmed value overtakes it.
Returns the implied operator/module stake delta via the internal helper path.
Decreases for active validators are intentionally not applied here: the tracked extra stays at the
highest observed level until withdrawal reporting settles any loss for penalty accounting.


```solidity
function reportValidatorBalance(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 nodeOperatorId,
    uint256 keyIndex,
    uint256 newConfirmed
) internal;
```

### _setOperatorBalance


```solidity
function _setOperatorBalance(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 operatorId,
    uint256 balanceWei
) private;
```

### _increaseKeyAllocatedBalance


```solidity
function _increaseKeyAllocatedBalance(
    mapping(uint256 => uint256) storage keyAllocatedBalance,
    uint256 nodeOperatorId,
    uint256 keyIndex,
    uint256 incrementWei
) private returns (uint256 appliedIncrementWei);
```

### _activeValidatorsCount


```solidity
function _activeValidatorsCount(NodeOperator storage no) private view returns (uint256);
```

### _activeModuleValidatorsCount


```solidity
function _activeModuleValidatorsCount(ModuleLinearStorage.BaseModuleStorage storage $)
    private
    view
    returns (uint256);
```

