# QueueLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/QueueLib.sol)

**Author:**
madlabman


## Functions
### clean

External methods


```solidity
function clean(
    Queue storage self,
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 maxItems,
    TransientUintUintMap queueLookup
) external returns (uint256 removed, uint256 lastRemovedAtDepth, uint256 visited, bool reachedOutOfQueue);
```

### enqueue

Internal methods


```solidity
function enqueue(Queue storage self, uint256 nodeOperatorId, uint256 keysCount) internal returns (Batch item);
```

### dequeue


```solidity
function dequeue(Queue storage self) internal returns (Batch item);
```

### peek


```solidity
function peek(Queue storage self) internal view returns (Batch);
```

### at


```solidity
function at(Queue storage self, uint128 index) internal view returns (Batch);
```

## Structs
### Queue

```solidity
struct Queue {
    // Pointer to the item to be dequeued.
    uint128 head;
    // Tracks the total number of batches ever enqueued.
    uint128 tail;
    // Mapping saves a little in costs and allows easily fallback to a zeroed batch on out-of-bounds access.
    mapping(uint128 => Batch) queue;
}
```

