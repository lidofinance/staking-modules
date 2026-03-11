# DepositQueueOps
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/DepositQueueOps.sol)


## Functions
### cleanDepositQueue


```solidity
function cleanDepositQueue(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 queueLowestPriority,
    uint256 maxItems
) external returns (uint256 removed, uint256 lastRemovedAtDepth);
```

### enqueueNodeOperatorKeys


```solidity
function enqueueNodeOperatorKeys(
    ModuleLinearStorage.BaseModuleStorage storage $,
    IParametersRegistry parametersRegistry,
    IAccounting accounting,
    uint256 queueLowestPriority,
    uint256 nodeOperatorId
) external;
```

### _clean


```solidity
function _clean(
    DepositQueueLib.Queue storage queue,
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 maxItems,
    TransientUintUintMap queueLookup
) private returns (uint256 removed, uint256 lastRemovedAtDepth, uint256 visited, bool reachedOutOfQueue);
```

### _enqueueNodeOperatorKeys


```solidity
function _enqueueNodeOperatorKeys(
    DepositQueueLib.Queue storage queue,
    NodeOperator storage no,
    uint256 nodeOperatorId,
    uint256 queuePriority,
    uint32 count
) private;
```

