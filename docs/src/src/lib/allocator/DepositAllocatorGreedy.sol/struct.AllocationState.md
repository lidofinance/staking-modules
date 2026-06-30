# AllocationState
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/allocator/DepositAllocatorGreedy.sol)

Helper struct for input allocation state.


```solidity
struct AllocationState {
/// @dev Target share per operator scaled by S_SCALE (X96).
uint256[] sharesX96;
/// @dev Current allocated amount per operator.
uint256[] currents;
/// @dev Remaining capacity per operator (max allocatable).
uint256[] capacities;
/// @dev Sum of current amounts across all operators.
uint256 totalCurrent;
}
```

