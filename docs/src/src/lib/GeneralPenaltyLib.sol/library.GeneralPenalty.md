# GeneralPenalty
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/GeneralPenaltyLib.sol)

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

