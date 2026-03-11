# ExternalOperatorLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/ExternalOperatorLib.sol)


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

