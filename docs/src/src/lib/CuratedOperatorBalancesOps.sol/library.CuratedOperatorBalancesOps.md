# CuratedOperatorBalancesOps
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/CuratedOperatorBalancesOps.sol)

The library is used to reduce CuratedModule bytecode size and keep balance ops centralized.


## Functions
### applyReportedBalances


```solidity
function applyReportedBalances(
    mapping(uint256 => uint256) storage operatorBalances,
    uint256 nodeOperatorsCount,
    bytes calldata operatorIds,
    bytes calldata totalBalancesGwei
) external;
```

### increaseByAllocations


```solidity
function increaseByAllocations(
    mapping(uint256 => uint256) storage operatorBalances,
    uint256[] calldata uniqueOperatorIds,
    uint256[] calldata perOperatorIncrements
) external;
```

### increaseBalance


```solidity
function increaseBalance(
    mapping(uint256 => uint256) storage operatorBalances,
    uint256 operatorId,
    uint256 incrementWei
) external;
```

### _setBalance


```solidity
function _setBalance(mapping(uint256 => uint256) storage operatorBalances, uint256 operatorId, uint256 balanceWei)
    private;
```

