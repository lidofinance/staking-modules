# FeeSplits
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/abstract/FeeSplits.sol)

**Inherits:**
[IFeeSplits](/src/interfaces/IFeeSplits.sol/interface.IFeeSplits.md)

Fee split mechanics abstract contract
It gives the ability to:
- set fee split recipients and shares for Node Operators
- split rewards between recipients and keep the remainder on the bond
- track pending shares waiting to be split
Internal non-view methods should be used in the Module contract with
additional requirements (if any).


## State Variables
### FEE_SPLITS_STORAGE_LOCATION

```solidity
bytes32 private constant FEE_SPLITS_STORAGE_LOCATION =
    0xac5584dcb35bfb1b3f4187762b10cb284ff937e63b5eb675e2e8e8876c7ee000
```


### MAX_BP

```solidity
uint256 internal constant MAX_BP = 10_000
```


### MAX_FEE_SPLITS

```solidity
uint256 public constant MAX_FEE_SPLITS = 10
```


## Functions
### getFeeSplits

Get fee splits for the given Node Operator


```solidity
function getFeeSplits(uint256 nodeOperatorId) external view returns (FeeSplit[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`FeeSplit[]`|Array of FeeSplit structs defining recipients and their shares in basis points|


### getPendingSharesToSplit

Get the number of the pending shares to be split for the given Node Operator


```solidity
function getPendingSharesToSplit(uint256 nodeOperatorId) public view returns (uint256);
```

### getFeeSplitTransfers

Calculate fee split transfers for the given Node Operator


```solidity
function getFeeSplitTransfers(uint256 nodeOperatorId, uint256 splittableShares)
    public
    view
    returns (SplitTransfer[] memory transfers);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`splittableShares`|`uint256`|Shares amount that can be split according to the current state of the Node Operator rewards and pending shares to split getPendingSharesToSplit() + FeeDistributor.getFeesToDistribute()|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`transfers`|`SplitTransfer[]`|Shares amounts to transfer to each split recipient|


### hasSplits

Check if the given Node Operator has fee splits


```solidity
function hasSplits(uint256 nodeOperatorId) public view returns (bool);
```

### _updateFeeSplits


```solidity
function _updateFeeSplits(uint256 nodeOperatorId, FeeSplit[] calldata feeSplits) internal;
```

### _increasePendingSharesToSplit


```solidity
function _increasePendingSharesToSplit(uint256 nodeOperatorId, uint256 shares) internal;
```

### _decreasePendingSharesToSplit


```solidity
function _decreasePendingSharesToSplit(uint256 nodeOperatorId, uint256 shares) internal;
```

### _getFeeSplitsStorage


```solidity
function _getFeeSplitsStorage() internal pure returns (FeeSplitsStorage storage $);
```

### _validateFeeSplits


```solidity
function _validateFeeSplits(FeeSplit[] calldata feeSplits) private pure returns (uint256 len);
```

## Structs
### FeeSplitsStorage
**Note:**
storage-location: erc7201:FeeSplits


```solidity
struct FeeSplitsStorage {
    mapping(uint256 nodeOperatorId => FeeSplit[]) feeSplits;
    // NOTE: Contains operator's and splits recipients' shares. May accumulate over time.
    mapping(uint256 nodeOperatorId => uint256 pendingToSplit) pendingSharesToSplit;
}
```

