# fls
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/GIndex.sol)

Find last set.
Returns the index of the most significant bit of `x`,
counting from the least significant bit position.
If `x` is zero, returns 256.


```solidity
function fls(uint256 x) pure returns (uint256 r);
```

