# WithdrawnValidatorInfo
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IBaseModule.sol)


```solidity
struct WithdrawnValidatorInfo {
uint256 nodeOperatorId;
// Index of the withdrawn key in the Node Operator's keys storage.
uint256 keyIndex;
// Balance to be used to calculate penalties. For a regular withdrawal of a validator it's the withdrawal amount.
// For a slashed validator it's its balance before slashing if slashing penalty is provided explicitly, otherwise it's the balance after slashing to calculate penalty using a less precise on-chain fallback.
// The balance will be used to scale incurred penalties and calculate penalties due to offline or slashing penalties via the shortcut mechanism.
uint256 exitBalance;
// Amount of ETH/stETH to penalize Node Operator due to slashing.
uint256 slashingPenalty;
// Whether the validator has been slashed.
bool isSlashed;
}
```

