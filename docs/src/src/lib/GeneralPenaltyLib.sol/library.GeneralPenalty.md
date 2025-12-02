# GeneralPenalty
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/GeneralPenaltyLib.sol)


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

