# IFeeSplits
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IFeeSplits.sol)


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
function getPendingSharesToSplit(uint256 nodeOperatorId) external view returns (uint256);
```

### hasSplits

Check if the given Node Operator has fee splits


```solidity
function hasSplits(uint256 nodeOperatorId) external view returns (bool);
```

### getFeeSplitTransfers

Calculate fee split transfers for the given Node Operator


```solidity
function getFeeSplitTransfers(uint256 nodeOperatorId, uint256 splittableShares)
    external
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


## Events
### FeeSplitsSet

```solidity
event FeeSplitsSet(uint256 indexed nodeOperatorId, FeeSplit[] feeSplits);
```

### PendingSharesToSplitChanged

```solidity
event PendingSharesToSplitChanged(uint256 indexed nodeOperatorId, uint256 pendingSharesToSplit);
```

## Errors
### PendingSharesExist

```solidity
error PendingSharesExist();
```

### FeeSplitsChangeWithUndistributedRewards

```solidity
error FeeSplitsChangeWithUndistributedRewards();
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

## Structs
### FeeSplit

```solidity
struct FeeSplit {
    address recipient;
    uint256 share; // in basis points
}
```

### SplitTransfer

```solidity
struct SplitTransfer {
    address recipient;
    uint256 shares;
}
```

