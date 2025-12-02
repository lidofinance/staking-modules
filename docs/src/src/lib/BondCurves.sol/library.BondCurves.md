# BondCurves
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/BondCurves.sol)

Library for managing BondCurves


## State Variables
### MIN_CURVE_LENGTH

```solidity
uint256 public constant MIN_CURVE_LENGTH = 1
```


### MAX_CURVE_LENGTH

```solidity
uint256 public constant MAX_CURVE_LENGTH = 100
```


## Functions
### addBondCurve

Add a new bond curve to the array


```solidity
function addBondCurve(
    BondCurve.BondCurveStorage storage bondCurvesStorage,
    IBondCurve.BondCurveIntervalInput[] calldata intervals
) external returns (uint256 curveId);
```

### updateBondCurve

Update existing bond curve


```solidity
function updateBondCurve(
    BondCurve.BondCurveStorage storage bondCurvesStorage,
    uint256 curveId,
    IBondCurve.BondCurveIntervalInput[] calldata intervals
) external;
```

### getBondAmountByKeysCount


```solidity
function getBondAmountByKeysCount(
    BondCurve.BondCurveStorage storage bondCurvesStorage,
    uint256 keys,
    uint256 curveId
) external view returns (uint256);
```

### getKeysCountByBondAmount


```solidity
function getKeysCountByBondAmount(
    BondCurve.BondCurveStorage storage bondCurvesStorage,
    uint256 amount,
    uint256 curveId
) external view returns (uint256);
```

### _addIntervals


```solidity
function _addIntervals(
    IBondCurve.BondCurveData storage bondCurve,
    IBondCurve.BondCurveIntervalInput[] calldata intervals
) internal;
```

### _check


```solidity
function _check(IBondCurve.BondCurveIntervalInput[] calldata intervals) internal pure;
```

