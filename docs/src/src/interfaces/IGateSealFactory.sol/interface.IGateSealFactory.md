# IGateSealFactory
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IGateSealFactory.sol)


## Functions
### create_gate_seal


```solidity
function create_gate_seal(
    address sealingCommittee,
    uint256 sealDurationSeconds,
    address[] memory sealables,
    uint256 expiryTimestamp
) external;
```

## Events
### GateSealCreated

```solidity
event GateSealCreated(address gateSeal);
```

