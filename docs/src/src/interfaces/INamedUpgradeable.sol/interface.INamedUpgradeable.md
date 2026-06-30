# INamedUpgradeable
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/interfaces/INamedUpgradeable.sol)

**Title:**
Named Upgradeable Interface

Common surface for contracts with an upgrade-safe human-readable name.


## Functions
### name


```solidity
function name() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Human-readable name|


### setName

Update the human-readable name


```solidity
function setName(string calldata name) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|New name|


## Events
### NameSet
Emitted when the display name is set


```solidity
event NameSet(string name);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|Human-readable name|

## Errors
### InvalidName

```solidity
error InvalidName();
```

