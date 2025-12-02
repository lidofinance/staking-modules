# WithdrawnValidatorLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/WithdrawnValidatorLib.sol)

A library to extract a part of the code from the the CSModule contract.


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
### process


```solidity
function process(WithdrawnValidatorInfo calldata validatorInfo) external returns (bool bondCoversPenalties);
```

### _fulfilExitObligations


```solidity
function _fulfilExitObligations(WithdrawnValidatorInfo calldata validatorInfo, ExitPenaltyInfo memory penaltyInfo)
    internal
    returns (bool bondCoversPenalties);
```

### _getPenaltyMultiplier

Acts as the numerator to calculate the scaled penalty.


```solidity
function _getPenaltyMultiplier(WithdrawnValidatorInfo memory validatorInfo)
    internal
    pure
    returns (uint256 penaltyMultiplier);
```

### _scalePenaltyByMultiplier


```solidity
function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256);
```

