# createBatch
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/QueueLib.sol)

Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.

Parameters are uint256 to make usage easier.


```solidity
function createBatch(uint256 nodeOperatorId, uint256 keysCount) pure returns (Batch item);
```

