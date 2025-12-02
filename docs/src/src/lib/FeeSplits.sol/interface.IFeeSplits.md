# IFeeSplits
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/FeeSplits.sol)

Library for managing FeeSplits

the only use of this to be a library is to save Accounting contract size via delegatecalls


## Events
### FeeSplitsSet

```solidity
event FeeSplitsSet(uint256 indexed nodeOperatorId, IAccounting.FeeSplit[] feeSplits);
```

## Errors
### PendingSharesExist

```solidity
error PendingSharesExist();
```

### UndistributedSharesExist

```solidity
error UndistributedSharesExist();
```

### TooManySplits

```solidity
error TooManySplits();
```

### TooManySplitShares

```solidity
error TooManySplitShares();
```

### ZeroSplitRecipient

```solidity
error ZeroSplitRecipient();
```

### ZeroSplitShare

```solidity
error ZeroSplitShare();
```

