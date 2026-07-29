# ExternalOperatorLib
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/ExternalOperatorLib.sol)


## State Variables
### ENTRY_LEN_NOR

```solidity
uint256 public constant ENTRY_LEN_NOR = 10
```


## Functions
### uniqueKey


```solidity
function uniqueKey(IMetaRegistry.ExternalOperator memory self) internal pure returns (bytes32);
```

### tryGetExtOpType


```solidity
function tryGetExtOpType(IMetaRegistry.ExternalOperator memory self) internal pure returns (OperatorType);
```

### unpackEntryTypeNOR


```solidity
function unpackEntryTypeNOR(IMetaRegistry.ExternalOperator memory self)
    internal
    pure
    returns (uint8 moduleId_, uint64 noId_);
```

### _isNOR


```solidity
function _isNOR(bytes memory data) internal pure returns (bool);
```

### _noIdNOR


```solidity
function _noIdNOR(bytes memory data) private pure returns (uint64 ret);
```

### _moduleIdNOR


```solidity
function _moduleIdNOR(bytes memory data) private pure returns (uint8);
```

## Errors
### InvalidExternalOperatorDataEntry

```solidity
error InvalidExternalOperatorDataEntry();
```

