# fls
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/GIndex.sol)

Find last set.
Returns the index of the most significant bit of `x`,
counting from the least significant bit position.
If `x` is zero, returns 256.


```solidity
function fls(uint256 x) pure returns (uint256 r);
```

