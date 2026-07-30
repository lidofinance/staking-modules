# WithdrawnValidatorLib
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/WithdrawnValidatorLib.sol)

External deployment-linked library used by BaseModule-compatible modules
to extract withdrawn validator processing from module bytecode.


## State Variables
### PENALTY_QUOTIENT

```solidity
uint256 public constant PENALTY_QUOTIENT = 1 ether
```


### PENALTY_SCALE
Acts as the denominator to calculate the scaled penalty.


```solidity
uint256 public constant PENALTY_SCALE = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT
```


## Functions
### rebuildTotalWithdrawnValidators


```solidity
function rebuildTotalWithdrawnValidators(ModuleLinearStorage.BaseModuleStorage storage $) external;
```

### processBatch


```solidity
function processBatch(
    WithdrawnValidatorInfo[] calldata validatorInfos,
    bool slashed,
    ModuleLinearStorage.BaseModuleStorage storage $
)
    external
    returns (uint256[] memory touchedOperatorIds, uint256[] memory trackedBalanceDecreases, uint256 touchedCount);
```

### _process


```solidity
function _process(
    NodeOperator storage no,
    WithdrawnValidatorInfo calldata validatorInfo,
    uint256 keyConfirmedBalance
) private;
```

### _fulfillExitObligations


```solidity
function _fulfillExitObligations(
    WithdrawnValidatorInfo calldata validatorInfo,
    ExitPenaltyInfo memory penaltyInfo,
    uint256 keyConfirmedBalance
) private;
```

### _getPenaltyMultiplier

Acts as the numerator to calculate the scaled penalty.

Expects the `balance` value between MIN_ACTIVATION_BALANCE and MAX_EFFECTIVE_BALANCE.


```solidity
function _getPenaltyMultiplier(uint256 balance) internal pure returns (uint256 penaltyMultiplier);
```

### _scalePenaltyByMultiplier


```solidity
function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256);
```

### _clamp


```solidity
function _clamp(uint256 v, uint256 min, uint256 max) internal pure returns (uint256);
```

