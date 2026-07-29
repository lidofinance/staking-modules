# createBatch
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/DepositQueueLib.sol)

Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.

Parameters are uint256 to make usage easier.


```solidity
function createBatch(uint256 nodeOperatorId, uint256 keysCount) pure returns (Batch item);
```

