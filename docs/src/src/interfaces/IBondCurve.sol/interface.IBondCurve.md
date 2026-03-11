# IBondCurve
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IBondCurve.sol)


## Functions
### DEFAULT_BOND_CURVE_ID


```solidity
function DEFAULT_BOND_CURVE_ID() external view returns (uint256);
```

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
function getBondCurveId(uint256 nodeOperatorId) external view returns (uint256);
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
function getBondAmountByKeysCount(uint256 keys, uint256 curveId) external view returns (uint256);
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
function getKeysCountByBondAmount(uint256 amount, uint256 curveId) external view returns (uint256);
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


## Events
### BondCurveAdded

```solidity
event BondCurveAdded(uint256 indexed curveId, BondCurveIntervalInput[] bondCurveIntervals);
```

### BondCurveUpdated

```solidity
event BondCurveUpdated(uint256 indexed curveId, BondCurveIntervalInput[] bondCurveIntervals);
```

### BondCurveSet

```solidity
event BondCurveSet(uint256 indexed nodeOperatorId, uint256 curveId);
```

## Errors
### InvalidBondCurveLength

```solidity
error InvalidBondCurveLength();
```

### InvalidBondCurveValues

```solidity
error InvalidBondCurveValues();
```

### InvalidBondCurveId

```solidity
error InvalidBondCurveId();
```

### InvalidInitializationCurveId

```solidity
error InvalidInitializationCurveId();
```

### SameBondCurveId

```solidity
error SameBondCurveId();
```

## Structs
### BondCurveData
Bond curve structure.
It contains:
- intervals    |> intervals-based representation of the bond curve
The interval is defined by:
- minKeysCount |> minimum keys count (inclusive) of the interval
- minBond      |> minimum bond amount (inclusive) of the interval
- trend        |> trend of the bond amount in the interval
For example, how the curve intervals look like:
Interval 0: minKeysCount = 1, minBond = 2 ETH, trend = 2 ETH
Interval 1: minKeysCount = 2, minBond = 3.9 ETH, trend = 1.9 ETH
Interval 2: minKeysCount = 3, minBond = 5.7 ETH, trend = 1.8 ETH
Bond Amount (ETH)
^
|
6 -
| ------------------ 5.7 ETH --> .
5.5 -                              ..^
|                             .  |
5 -                            .   |
|                           .    |
4.5 -                          .     |
|                         .      |
4 -                       ..       |
| ------- 3.9 ETH --> ..         |
3.5 -                    .^          |
|                  .. |          |
3 -                ..   |          |
|               .     |          |
2.5 -              .      |          |
|            ..       |          |
2 - -------->..         |          |
|          ^          |          |
|----------|----------|----------|----------|----> Keys Count
|          1          2          3          i


```solidity
struct BondCurveData {
    BondCurveInterval[] intervals;
}
```

### BondCurveInterval

```solidity
struct BondCurveInterval {
    uint256 minKeysCount;
    uint256 minBond;
    uint256 trend;
}
```

### BondCurveIntervalInput

```solidity
struct BondCurveIntervalInput {
    uint256 minKeysCount;
    uint256 trend;
}
```

