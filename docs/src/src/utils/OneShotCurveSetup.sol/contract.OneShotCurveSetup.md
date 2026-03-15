# OneShotCurveSetup
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/utils/OneShotCurveSetup.sol)

**Inherits:**
[IOneShotCurveSetup](/src/interfaces/IOneShotCurveSetup.sol/interface.IOneShotCurveSetup.md)

Helper that atomically deploys a new bond curve together with its parameter overrides.

The contract is intentionally single-use: once `execute` finishes successfully it
stores the emitted `curveId` for reference.
Permission model: grant only two temporary roles to this contract:
`ACCOUNTING.MANAGE_BOND_CURVES_ROLE()` and `REGISTRY.MANAGE_CURVE_PARAMETERS_ROLE()`.
After successful execution, the contract renounces both roles.


## State Variables
### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### REGISTRY

```solidity
IParametersRegistry public immutable REGISTRY
```


### executed

```solidity
bool public executed
```


### deployedCurveId

```solidity
uint256 public deployedCurveId
```


### bondCurve

```solidity
IBondCurve.BondCurveIntervalInput[] public bondCurve
```


### keyRemovalChargeOverride

```solidity
ScalarOverride public keyRemovalChargeOverride
```


### generalDelayedPenaltyFineOverride

```solidity
ScalarOverride public generalDelayedPenaltyFineOverride
```


### keysLimitOverride

```solidity
ScalarOverride public keysLimitOverride
```


### queueConfigOverride

```solidity
QueueConfigOverride public queueConfigOverride
```


### rewardShareDataOverride

```solidity
KeyNumberValueIntervalsOverride public rewardShareDataOverride
```


### performanceLeewayDataOverride

```solidity
KeyNumberValueIntervalsOverride public performanceLeewayDataOverride
```


### strikesParamsOverride

```solidity
StrikesOverride public strikesParamsOverride
```


### badPerformancePenaltyOverride

```solidity
ScalarOverride public badPerformancePenaltyOverride
```


### performanceCoefficientsOverride

```solidity
PerformanceCoefficientsOverride public performanceCoefficientsOverride
```


### allowedExitDelayOverride

```solidity
ScalarOverride public allowedExitDelayOverride
```


### exitDelayFeeOverride

```solidity
ScalarOverride public exitDelayFeeOverride
```


### maxElWithdrawalRequestFeeOverride

```solidity
ScalarOverride public maxElWithdrawalRequestFeeOverride
```


## Functions
### constructor


```solidity
constructor(address accounting_, address registry_, ConstructorParams memory params) ;
```

### execute


```solidity
function execute() external override returns (uint256 curveId);
```

### getBondCurve


```solidity
function getBondCurve() external view override returns (IBondCurve.BondCurveIntervalInput[] memory bondCurve_);
```

### getRewardShareDataOverride


```solidity
function getRewardShareDataOverride()
    external
    view
    override
    returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);
```

### getPerformanceLeewayDataOverride


```solidity
function getPerformanceLeewayDataOverride()
    external
    view
    override
    returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);
```

### _applyParameterOverrides


```solidity
function _applyParameterOverrides(uint256 curveId) internal;
```

### _storeBondCurve


```solidity
function _storeBondCurve(IBondCurve.BondCurveIntervalInput[] memory source) internal;
```

### _storeIntervals


```solidity
function _storeIntervals(
    KeyNumberValueIntervalsOverride memory source,
    KeyNumberValueIntervalsOverride storage target
) internal;
```

