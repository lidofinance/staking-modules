# BondCurve
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/abstract/BondCurve.sol)

**Inherits:**
[IBondCurve](/src/interfaces/IBondCurve.sol/interface.IBondCurve.md), Initializable

**Author:**
vgorkavenko

Bond curve mechanics abstract contract
It gives the ability to build bond curves for flexible bond math.
There is a default bond curve for all Node Operators, which might be 'overridden' for a particular Node Operator.
It contains:
- add bond curve
- get bond curve info
- set default bond curve
- set bond curve for the given Node Operator
- get bond curve for the given Node Operator
- get required bond amount for the given keys count
- get keys count for the given bond amount
It should be inherited by a module contract or a module-related contract.
Internal non-view methods should be used in the Module contract with additional requirements (if any).


## State Variables
### BOND_CURVE_STORAGE_LOCATION

```solidity
bytes32 private constant BOND_CURVE_STORAGE_LOCATION =
    0x8f22e270e477f5becb8793b61d439ab7ae990ed8eba045eb72061c0e6cfe1500
```


### DEFAULT_BOND_CURVE_ID

```solidity
uint256 public constant DEFAULT_BOND_CURVE_ID = 0
```


## Functions
### getCurvesCount

Get the number of available curves


```solidity
function getCurvesCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of available curves|


### getCurveInfo

Return bond curve for the given curve id

Reverts if `curveId` is invalid


```solidity
function getCurveInfo(uint256 curveId) external view returns (BondCurveData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve id to get bond curve for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BondCurveData`|Bond curve|


### getBondCurve

Get bond curve for the given Node Operator


```solidity
function getBondCurve(uint256 nodeOperatorId) external view returns (BondCurveData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BondCurveData`|Bond curve|


### getBondCurveId

Get bond curve ID for the given Node Operator


```solidity
function getBondCurveId(uint256 nodeOperatorId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Bond curve ID|


### getBondAmountByKeysCount

Get required bond in ETH for the given number of keys for the given bond curve

To calculate the amount for the new keys 2 calls are required:
getBondAmountByKeysCount(newTotal) - getBondAmountByKeysCount(currentTotal)


```solidity
function getBondAmountByKeysCount(uint256 keys, uint256 curveId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keys`|`uint256`|Number of keys to get required bond for|
|`curveId`|`uint256`|Id of the curve to perform calculations against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Amount for particular keys count|


### getKeysCountByBondAmount

Get keys count for the given bond amount with the given bond curve


```solidity
function getKeysCountByBondAmount(uint256 amount, uint256 curveId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Bond amount in ETH (stETH) to get keys count for|
|`curveId`|`uint256`|Id of the curve to perform calculations against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Keys count|


### __BondCurve_init


```solidity
function __BondCurve_init(BondCurveIntervalInput[] calldata defaultBondCurveIntervals) internal onlyInitializing;
```

### _addBondCurve

Add a new bond curve to the array


```solidity
function _addBondCurve(BondCurveIntervalInput[] calldata intervals) internal returns (uint256 curveId);
```

### _updateBondCurve

Update existing bond curve


```solidity
function _updateBondCurve(uint256 curveId, BondCurveIntervalInput[] calldata intervals) internal;
```

### _setBondCurve

Sets bond curve for the given Node Operator
It will be used for the Node Operator instead of the previously set curve


```solidity
function _setBondCurve(uint256 nodeOperatorId, uint256 curveId) internal;
```

### _getCurveInfo


```solidity
function _getCurveInfo(uint256 curveId) private view returns (BondCurveData storage);
```

### _getBondCurveStorage


```solidity
function _getBondCurveStorage() private pure returns (BondCurveStorage storage $);
```

## Structs
### BondCurveStorage
**Note:**
storage-location: erc7201:CSBondCurve


```solidity
struct BondCurveStorage {
    /// @dev DEPRECATED. DO NOT USE. Preserves storage layout. Previous structure occupied 3 slots per item.
    bytes32[] legacyBondCurves;
    /// @dev Mapping of Node Operator id to bond curve id
    mapping(uint256 nodeOperatorId => uint256 bondCurveId) operatorBondCurveId;
    BondCurveData[] bondCurves;
}
```

