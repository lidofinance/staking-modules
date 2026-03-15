# GeneralPenalty
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/GeneralPenaltyLib.sol)

Library for General Penalty logic

the only use of this to be a library is to save CSModule contract size via delegatecalls


## Functions
### reportGeneralDelayedPenalty


```solidity
function reportGeneralDelayedPenalty(
    uint256 nodeOperatorId,
    bytes32 penaltyType,
    uint256 amount,
    string calldata details
) external;
```

### cancelGeneralDelayedPenalty


```solidity
function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount) external;
```

### settleGeneralDelayedPenalty


```solidity
function settleGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 maxAmount) external returns (bool);
```

### compensateGeneralDelayedPenalty


```solidity
function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external;
```

