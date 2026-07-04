# TopUpQueueLib
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/TopUpQueueLib.sol)


## Functions
### enqueue


```solidity
function enqueue(Queue storage self, TopUpQueueItem item) internal;
```

### dequeue


```solidity
function dequeue(Queue storage self) internal;
```

### rewind


```solidity
function rewind(Queue storage self, uint32 to) internal;
```

### capacity


```solidity
function capacity(Queue storage self) internal view returns (uint256);
```

### length


```solidity
function length(Queue storage self) internal view returns (uint256);
```

### at


```solidity
function at(Queue storage self, uint256 index) internal view returns (TopUpQueueItem);
```

## Structs
### Queue

```solidity
struct Queue {
    TopUpQueueItem[] items;
    uint32 head;
    uint8 limit;
    bool enabled;
}
```

