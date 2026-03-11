# fls
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/GIndex.sol)

Find last set.
Returns the index of the most significant bit of `x`,
counting from the least significant bit position.
If `x` is zero, returns 256.


```solidity
function fls(uint256 x) pure returns (uint256 r);
```

