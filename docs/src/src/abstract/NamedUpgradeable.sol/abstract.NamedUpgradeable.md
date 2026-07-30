# NamedUpgradeable
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/abstract/NamedUpgradeable.sol)

**Inherits:**
[INamedUpgradeable](/src/interfaces/INamedUpgradeable.sol/interface.INamedUpgradeable.md)


## State Variables
### MAX_NAME_LENGTH

```solidity
uint256 internal constant MAX_NAME_LENGTH = 256
```


### NAMED_UPGRADEABLE_STORAGE_LOCATION

```solidity
bytes32 private constant NAMED_UPGRADEABLE_STORAGE_LOCATION =
    0xf31ae013a5af13f77f257862ecd68bd4c15a1f200f6be2d419997a40372cfa00
```


## Functions
### name


```solidity
function name() public view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Human-readable name|


### _setName


```solidity
function _setName(string calldata name_) internal;
```

### _getNamedUpgradeableStorage


```solidity
function _getNamedUpgradeableStorage() private pure returns (NamedUpgradeableStorage storage $);
```

## Structs
### NamedUpgradeableStorage
**Note:**
storage-location: erc7201:NamedUpgradeable


```solidity
struct NamedUpgradeableStorage {
    string name;
}
```

