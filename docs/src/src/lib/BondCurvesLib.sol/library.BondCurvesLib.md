# BondCurvesLib
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/BondCurvesLib.sol)

Library for managing BondCurves

External deployment-linked library used by Accounting.


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
    BondCurve.BondCurveStorage storage bondCurveStorage,
    IBondCurve.BondCurveIntervalInput[] calldata intervals
) external returns (uint256 curveId);
```

### updateBondCurve

Update existing bond curve


```solidity
function updateBondCurve(
    BondCurve.BondCurveStorage storage bondCurveStorage,
    uint256 curveId,
    IBondCurve.BondCurveIntervalInput[] calldata intervals
) external;
```

### getBondAmountByKeysCount


```solidity
function getBondAmountByKeysCount(
    BondCurve.BondCurveStorage storage bondCurveStorage,
    uint256 keys,
    uint256 curveId
) external view returns (uint256);
```

### getKeysCountByBondAmount


```solidity
function getKeysCountByBondAmount(
    BondCurve.BondCurveStorage storage bondCurveStorage,
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

### _ensureCurveExists


```solidity
function _ensureCurveExists(BondCurve.BondCurveStorage storage bondCurveStorage, uint256 curveId) internal view;
```

### _check


```solidity
function _check(IBondCurve.BondCurveIntervalInput[] calldata intervals) internal pure;
```

