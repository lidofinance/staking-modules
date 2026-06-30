# GeneralPenalty
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/GeneralPenaltyLib.sol)

Library for General Penalty logic

External deployment-linked library used by BaseModule-compatible modules
to save contract size via delegatecalls.


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
function settleGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 bondLockNonce) external returns (bool);
```

### compensateGeneralDelayedPenalty


```solidity
function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external;
```

