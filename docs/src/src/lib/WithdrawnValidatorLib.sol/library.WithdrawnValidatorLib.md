# WithdrawnValidatorLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/WithdrawnValidatorLib.sol)

A library to extract a part of the code from the CSModule contract.


## State Variables
### MAX_EFFECTIVE_BALANCE

```solidity
uint256 public constant MAX_EFFECTIVE_BALANCE = 2048 ether
```


### MIN_ACTIVATION_BALANCE

```solidity
uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether
```


### PENALTY_QUOTIENT

```solidity
uint256 public constant PENALTY_QUOTIENT = 1 ether
```


### PENALTY_SCALE
Acts as the denominator to calculate the scaled penalty.


```solidity
uint256 public constant PENALTY_SCALE = MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT
```


## Functions
### processBatch


```solidity
function processBatch(
    WithdrawnValidatorInfo[] calldata validatorInfos,
    bool slashed,
    ModuleLinearStorage.BaseModuleStorage storage $
) external returns (uint256[] memory touchedOperatorIds, uint256 touchedCount);
```

### _process


```solidity
function _process(NodeOperator storage no, WithdrawnValidatorInfo calldata validatorInfo, uint256 keyAddedBalance)
    private;
```

### _fulfillExitObligations


```solidity
function _fulfillExitObligations(
    WithdrawnValidatorInfo calldata validatorInfo,
    ExitPenaltyInfo memory penaltyInfo,
    uint256 keyAddedBalance
) internal;
```

### _getPenaltyMultiplier

Acts as the numerator to calculate the scaled penalty.


```solidity
function _getPenaltyMultiplier(uint256 balance) internal pure returns (uint256 penaltyMultiplier);
```

### _scalePenaltyByMultiplier


```solidity
function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256);
```

### _keyPointer


```solidity
function _keyPointer(uint256 nodeOperatorId, uint256 keyIndex) internal pure returns (uint256 pointer);
```

