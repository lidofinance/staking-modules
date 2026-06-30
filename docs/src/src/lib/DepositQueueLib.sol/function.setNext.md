# setNext
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/DepositQueueLib.sol)

can be unsafe if the From batch is previous to the self


```solidity
function setNext(Batch self, uint128 nextIndex) pure returns (Batch);
```

