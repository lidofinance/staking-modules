# WithdrawnValidatorInfo
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/ICSModule.sol)


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

