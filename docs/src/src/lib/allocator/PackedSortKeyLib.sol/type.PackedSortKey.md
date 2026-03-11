# PackedSortKey
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/allocator/PackedSortKeyLib.sol)

Packed sort key used for ordering operators by imbalance.

Layout:
- high 224 bits: imbalance
- low 32 bits: reversed index (`INDEX_MASK - idx`) so lower original index wins ties.
Assumes `idx <= type(uint32).max`.


```solidity
type PackedSortKey is uint256
```

