# AllocationState
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/allocator/DepositAllocatorGreedy.sol)

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

