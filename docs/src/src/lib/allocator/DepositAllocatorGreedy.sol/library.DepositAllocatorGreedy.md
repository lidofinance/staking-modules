# DepositAllocatorGreedy
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/allocator/DepositAllocatorGreedy.sol)

Greedy imbalance math with the same entrypoints as DepositPouringMath.


## State Variables
### S_SCALE

```solidity
uint256 internal constant S_SCALE = uint256(1) << 96
```


## Functions
### _allocate

Expected input invariants:
- state.capacities[i] > 0
- state.sharesX96[i] > 0
- step > 0
- all arrays in state have the same length n, and entries correspond to the same operators across arrays.
for i in [0..n).


```solidity
function _allocate(AllocationState memory state, uint256 allocationAmount, uint256 step)
    internal
    pure
    returns (uint256 allocated, uint256[] memory allocations);
```

### _quantize


```solidity
function _quantize(uint256 value, uint256 step) internal pure returns (uint256);
```

### _maxHeapKeysByImbalanceDesc


```solidity
function _maxHeapKeysByImbalanceDesc(AllocationState memory state, uint256 allocationAmount, uint256 step)
    internal
    pure
    returns (PackedSortKey[] memory heap);
```

