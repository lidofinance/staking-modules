# WithdrawnValidatorInfo
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IBaseModule.sol)


```solidity
struct WithdrawnValidatorInfo {
uint256 nodeOperatorId;
// Index of the withdrawn key in the Node Operator's keys storage.
uint256 keyIndex;
// Balance to be used to calculate penalties. For a regular withdrawal of a validator it's the withdrawal amount.
// For a slashed validator it's its balance before slashing. The balance will be used to scale incurred penalties.
uint256 exitBalance;
// Amount of ETH/stETH to penalize Node Operator due to slashing.
uint256 slashingPenalty;
// Whether the validator has been slashed.
bool isSlashed;
}
```

