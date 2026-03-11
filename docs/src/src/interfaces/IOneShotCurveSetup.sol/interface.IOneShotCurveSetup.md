# IOneShotCurveSetup
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IOneShotCurveSetup.sol)

**Title:**
One-shot setup helper for a bond curve plus per-curve parameter overrides.

Intended for one-shot execution with temporary permissions only.
Required roles:
- `ACCOUNTING.MANAGE_BOND_CURVES_ROLE()`
- `REGISTRY.MANAGE_CURVE_PARAMETERS_ROLE()`
After `execute()` succeeds, this contract renounces both roles.


## Functions
### ACCOUNTING

Bond accounting contract that receives the new curve.


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### REGISTRY

Parameters registry whose per-curve overrides are configured.


```solidity
function REGISTRY() external view returns (IParametersRegistry);
```

### executed

Whether `execute()` already ran.


```solidity
function executed() external view returns (bool);
```

### deployedCurveId

Curve ID created by the successful `execute()` call.


```solidity
function deployedCurveId() external view returns (uint256);
```

### getBondCurve

Returns the stored bond curve to be deployed by `execute()`.


```solidity
function getBondCurve() external view returns (IBondCurve.BondCurveIntervalInput[] memory bondCurve);
```

### getRewardShareDataOverride

Returns whether reward share override is configured and the configured interval data.


```solidity
function getRewardShareDataOverride()
    external
    view
    returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);
```

### getPerformanceLeewayDataOverride

Returns whether performance leeway override is configured and the configured interval data.


```solidity
function getPerformanceLeewayDataOverride()
    external
    view
    returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);
```

### execute

Executes the stored rollout plan, adding the curve and applying the overrides.

Requires only:
`ACCOUNTING.MANAGE_BOND_CURVES_ROLE()` and `REGISTRY.MANAGE_CURVE_PARAMETERS_ROLE()`.
On success, both roles are renounced by this contract.


```solidity
function execute() external returns (uint256 curveId);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve ID allocated to the newly deployed bond curve.|


## Events
### BondCurveDeployed
Emitted once the curve setup completes successfully.


```solidity
event BondCurveDeployed(uint256 indexed curveId);
```

## Errors
### AlreadyExecuted

```solidity
error AlreadyExecuted();
```

### ZeroAccountingAddress

```solidity
error ZeroAccountingAddress();
```

### ZeroRegistryAddress

```solidity
error ZeroRegistryAddress();
```

### EmptyBondCurve

```solidity
error EmptyBondCurve();
```

## Structs
### ScalarOverride

```solidity
struct ScalarOverride {
    bool isSet;
    uint256 value;
}
```

### QueueConfigOverride

```solidity
struct QueueConfigOverride {
    bool isSet;
    uint256 priority;
    uint256 maxDeposits;
}
```

### StrikesOverride

```solidity
struct StrikesOverride {
    bool isSet;
    uint256 lifetime;
    uint256 threshold;
}
```

### PerformanceCoefficientsOverride

```solidity
struct PerformanceCoefficientsOverride {
    bool isSet;
    uint256 attestationsWeight;
    uint256 blocksWeight;
    uint256 syncWeight;
}
```

### KeyNumberValueIntervalsOverride

```solidity
struct KeyNumberValueIntervalsOverride {
    bool isSet;
    IParametersRegistry.KeyNumberValueInterval[] data;
}
```

### ConstructorParams

```solidity
struct ConstructorParams {
    IBondCurve.BondCurveIntervalInput[] bondCurve;
    ScalarOverride keyRemovalCharge;
    ScalarOverride generalDelayedPenaltyFine;
    ScalarOverride keysLimit;
    QueueConfigOverride queueConfig;
    KeyNumberValueIntervalsOverride rewardShareData;
    KeyNumberValueIntervalsOverride performanceLeewayData;
    StrikesOverride strikesParams;
    ScalarOverride badPerformancePenalty;
    PerformanceCoefficientsOverride performanceCoefficients;
    ScalarOverride allowedExitDelay;
    ScalarOverride exitDelayFee;
    ScalarOverride maxElWithdrawalRequestFee;
}
```

