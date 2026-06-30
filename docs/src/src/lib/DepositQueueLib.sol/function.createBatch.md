# createBatch
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/DepositQueueLib.sol)

Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.

Parameters are uint256 to make usage easier.


```solidity
function createBatch(uint256 nodeOperatorId, uint256 keysCount) pure returns (Batch item);
```

