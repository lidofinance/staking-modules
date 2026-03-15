# DepositQueueLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/DepositQueueLib.sol)

**Author:**
madlabman


## Functions
### enqueue

External methods
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
    // Tracks the index to enqueue an item to.
    uint128 tail;
    // Mapping saves a little in costs and allows easily fallback to a zeroed batch on out-of-bounds access.
    mapping(uint128 => Batch) queue;
}
```

