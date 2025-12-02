# fls
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/GIndex.sol)

From Solady LibBit, see https://github.com/Vectorized/solady/blob/main/src/utils/LibBit.sol.

Find last set.
Returns the index of the most significant bit of `x`,
counting from the least significant bit position.
If `x` is zero, returns 256.


```solidity
function fls(uint256 x) pure returns (uint256 r);
```

