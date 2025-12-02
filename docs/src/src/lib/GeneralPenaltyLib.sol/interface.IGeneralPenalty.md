# IGeneralPenalty
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/GeneralPenaltyLib.sol)

Library for General Penalty logic

the only use of this to be a library is to save CSModule contract size via delegatecalls


## Events
### GeneralDelayedPenaltyReported

```solidity
event GeneralDelayedPenaltyReported(
    uint256 indexed nodeOperatorId, bytes32 indexed penaltyType, uint256 amount, string details
);
```

### GeneralDelayedPenaltyCancelled

```solidity
event GeneralDelayedPenaltyCancelled(uint256 indexed nodeOperatorId, uint256 amount);
```

### GeneralDelayedPenaltyCompensated

```solidity
event GeneralDelayedPenaltyCompensated(uint256 indexed nodeOperatorId, uint256 amount);
```

### GeneralDelayedPenaltySettled

```solidity
event GeneralDelayedPenaltySettled(uint256 indexed nodeOperatorId);
```

## Errors
### ZeroPenaltyType

```solidity
error ZeroPenaltyType();
```

