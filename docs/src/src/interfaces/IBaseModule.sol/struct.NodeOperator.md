# NodeOperator
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IBaseModule.sol)


```solidity
struct NodeOperator {
// All the counters below are used together e.g. in the _updateDepositableValidatorsCount
/* 1 */ uint32 totalAddedKeys; // @dev increased and decreased when removed
/* 1 */ uint32 totalWithdrawnKeys; // @dev only increased
/* 1 */ uint32 totalDepositedKeys; // @dev only increased
/* 1 */ uint32 totalVettedKeys; // @dev both increased and decreased
/* 1 */ uint32 stuckValidatorsCount; // @dev both increased and decreased
/* 1 */ uint32 depositableValidatorsCount; // @dev any value
/* 1 */ uint32 targetLimit;
/* 1 */ uint8 targetLimitMode;
/* 2 */ uint32 totalExitedKeys; // @dev only increased except for the unsafe updates
/* 2 */ uint32 enqueuedCount; // Tracks how many places are occupied by the node operator's keys in the queue.
/* 2 */ address managerAddress;
/* 3 */ address proposedManagerAddress;
/* 4 */ address rewardAddress;
/* 5 */ address proposedRewardAddress;
/* 5 */ bool extendedManagerPermissions;
/* 5 */ bool usedPriorityQueue; // @dev no longer used, left for the storage layout compatibility
}
```

