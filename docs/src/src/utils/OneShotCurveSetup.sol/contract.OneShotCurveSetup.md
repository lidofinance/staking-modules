# OneShotCurveSetup
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/utils/OneShotCurveSetup.sol)

**Inherits:**
[IOneShotCurveSetup](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IOneShotCurveSetup.sol/interface.IOneShotCurveSetup.md)

Helper that atomically deploys a new bond curve together with its parameter overrides.

The contract is intentionally single-use: once `execute` finishes successfully it
stores the emitted `curveId` for reference.


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


### maxWithdrawalRequestFeeOverride

```solidity
ScalarOverride public maxWithdrawalRequestFeeOverride
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

