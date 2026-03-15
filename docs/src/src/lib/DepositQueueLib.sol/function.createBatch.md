# createBatch
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/DepositQueueLib.sol)

Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.

Parameters are uint256 to make usage easier.


```solidity
function createBatch(uint256 nodeOperatorId, uint256 keysCount) pure returns (Batch item);
```

