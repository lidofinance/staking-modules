# TopUpQueueLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/TopUpQueueLib.sol)


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

