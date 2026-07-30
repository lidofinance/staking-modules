# DepositQueueOps
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/DepositQueueOps.sol)

External deployment-linked library used by CSModule.


## Functions
### obtainDepositData


```solidity
function obtainDepositData(
    ModuleLinearStorage.BaseModuleStorage storage $,
    TopUpQueueLib.Queue storage topUpQueue,
    uint256 depositsCount,
    uint256 queueLowestPriority
) external returns (bytes memory publicKeys, bytes memory signatures);
```

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

### _enqueueTopUpKeys


```solidity
function _enqueueTopUpKeys(
    TopUpQueueLib.Queue storage topUpQueue,
    uint32 noId,
    uint32 keyIndexBase,
    uint32 keysCount
) private;
```

### _loadAndAccountDeposits


```solidity
function _loadAndAccountDeposits(
    TopUpQueueLib.Queue storage topUpQueue,
    NodeOperator storage no,
    uint32 noId,
    uint32 keysCount,
    ObtainDepositDataContext memory ctx
) private;
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

## Structs
### ObtainDepositDataContext

```solidity
struct ObtainDepositDataContext {
    uint256 loadedKeysCount;
    bytes publicKeys;
    bytes signatures;
}
```

