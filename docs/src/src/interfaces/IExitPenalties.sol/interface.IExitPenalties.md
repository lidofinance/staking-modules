# IExitPenalties
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IExitPenalties.sol)

**Inherits:**
[IExitTypes](/src/interfaces/IExitTypes.sol/interface.IExitTypes.md)


## Functions
### MODULE


```solidity
function MODULE() external view returns (IBaseModule);
```

### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### PARAMETERS_REGISTRY


```solidity
function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);
```

### STRIKES


```solidity
function STRIKES() external view returns (address);
```

### processExitDelayReport

Handles tracking and penalization logic for a validator that remains active beyond its eligible exit window.

see IStakingModule.reportValidatorExitDelay for details


```solidity
function processExitDelayReport(uint256 nodeOperatorId, bytes calldata publicKey, uint256 eligibleToExitInSec)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the node operator whose validator's status is being delivered.|
|`publicKey`|`bytes`|The public key of the validator being reported.|
|`eligibleToExitInSec`|`uint256`|The duration (in seconds) indicating how long the validator has been eligible to exit but has not exited.|


### processTriggeredExit

Process the triggered exit report


```solidity
function processTriggeredExit(
    uint256 nodeOperatorId,
    bytes calldata publicKey,
    uint256 elWithdrawalRequestFeePaid,
    uint256 exitType
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`publicKey`|`bytes`|Public key of the validator|
|`elWithdrawalRequestFeePaid`|`uint256`|The fee paid for the withdrawal request|
|`exitType`|`uint256`|The type of the exit; only `VOLUNTARY_EXIT_TYPE_ID` skips recording EL withdrawal request fee|


### processStrikesReport

Process the strikes report


```solidity
function processStrikesReport(uint256 nodeOperatorId, bytes calldata publicKey) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`publicKey`|`bytes`|Public key of the validator|


### isValidatorExitDelayPenaltyApplicable

Determines whether a validator exit status should be updated and will have affect on Node Operator.

called only by the module


```solidity
function isValidatorExitDelayPenaltyApplicable(
    uint256 nodeOperatorId,
    bytes calldata publicKey,
    uint256 eligibleToExitInSec
) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the node operator.|
|`publicKey`|`bytes`|Validator's public key.|
|`eligibleToExitInSec`|`uint256`|The number of seconds the validator was eligible to exit but did not.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Returns true if contract should receive updated validator's status.|


### getExitPenaltyInfo

get delayed exit penalty info for the given Node Operator


```solidity
function getExitPenaltyInfo(uint256 nodeOperatorId, bytes calldata publicKey)
    external
    view
    returns (ExitPenaltyInfo memory penaltyInfo);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`publicKey`|`bytes`|Public key of the validator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`penaltyInfo`|`ExitPenaltyInfo`|Delayed exit penalty info|


## Events
### ValidatorExitDelayProcessed

```solidity
event ValidatorExitDelayProcessed(uint256 indexed nodeOperatorId, bytes pubkey, uint256 delayFee);
```

### TriggeredExitFeeRecorded

```solidity
event TriggeredExitFeeRecorded(
    uint256 indexed nodeOperatorId,
    uint256 indexed exitType,
    bytes pubkey,
    uint256 withdrawalRequestPaidFee,
    uint256 withdrawalRequestRecordedFee
);
```

### StrikesPenaltyProcessed

```solidity
event StrikesPenaltyProcessed(uint256 indexed nodeOperatorId, bytes pubkey, uint256 strikesPenalty);
```

## Errors
### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroParametersRegistryAddress

```solidity
error ZeroParametersRegistryAddress();
```

### ZeroStrikesAddress

```solidity
error ZeroStrikesAddress();
```

### SenderIsNotModule

```solidity
error SenderIsNotModule();
```

### SenderIsNotStrikes

```solidity
error SenderIsNotStrikes();
```

### ValidatorExitDelayNotApplicable

```solidity
error ValidatorExitDelayNotApplicable();
```

