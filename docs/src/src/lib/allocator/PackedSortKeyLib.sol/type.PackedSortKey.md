# PackedSortKey
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/allocator/PackedSortKeyLib.sol)

Packed sort key used for ordering operators by imbalance.

Layout:
- high 224 bits: imbalance
- low 32 bits: reversed index (`INDEX_MASK - idx`) so lower original index wins ties.
Assumes `idx <= type(uint32).max`.
The packed representation can be compared directly as `uint256`, which makes it reusable across
full sorts, insertion sorts and max-heaps without custom comparator logic.


```solidity
type PackedSortKey is uint256
```

