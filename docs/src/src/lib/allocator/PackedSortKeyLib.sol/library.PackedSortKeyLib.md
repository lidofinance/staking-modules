# PackedSortKeyLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/allocator/PackedSortKeyLib.sol)

Helper functions to pack and unpack `PackedSortKey`.


## State Variables
### INDEX_BITS

```solidity
uint256 internal constant INDEX_BITS = 32
```


### INDEX_MASK

```solidity
uint256 internal constant INDEX_MASK = type(uint32).max
```


## Functions
### pack

Packs imbalance and index into a single sortable key.

Sorting packed keys in descending order produces:
- imbalance descending
- index ascending on equal imbalance.


```solidity
function pack(uint256 imbalance, uint256 idx) internal pure returns (PackedSortKey key);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`imbalance`|`uint256`|Operator imbalance value.|
|`idx`|`uint256`|Operator index in the source arrays.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PackedSortKey`|Packed key.|


### unpackIndex

Unpacks the original operator index from a packed key.


```solidity
function unpackIndex(PackedSortKey key) internal pure returns (uint256 idx);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PackedSortKey`|Packed key.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`idx`|`uint256`|Original operator index.|


### unpackImbalance

Unpacks imbalance from a packed key.


```solidity
function unpackImbalance(PackedSortKey key) internal pure returns (uint256 imbalance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PackedSortKey`|Packed key.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`imbalance`|`uint256`|Imbalance value.|


### asUint256Array

Reinterprets a packed key array as uint256[].

`PackedSortKey` wraps `uint256`, so both arrays have identical in-memory layout.
Useful for passing keys to helpers that accept `uint256[]` (e.g. `Arrays.sort`).


```solidity
function asUint256Array(PackedSortKey[] memory keys) internal pure returns (uint256[] memory out);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keys`|`PackedSortKey[]`|Packed key array.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`out`|`uint256[]`|Same array viewed as uint256[].|


