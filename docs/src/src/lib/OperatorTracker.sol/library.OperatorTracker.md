# OperatorTracker
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/OperatorTracker.sol)


## State Variables
### OPERATORS_CREATED_IN_TX_MAP_TSLOT

```solidity
bytes32 internal constant OPERATORS_CREATED_IN_TX_MAP_TSLOT =
    0x1b07bc0838fdc4254cbabb5dd0c94d936f872c6758547168d513d8ad1dc3a500
```


## Functions
### recordCreator


```solidity
function recordCreator(uint256 nodeOperatorId) internal;
```

### forgetCreator


```solidity
function forgetCreator(uint256 nodeOperatorId) internal;
```

### getCreator


```solidity
function getCreator(uint256 nodeOperatorId) internal view returns (address);
```

### map


```solidity
function map() private pure returns (TransientUintUintMap);
```

