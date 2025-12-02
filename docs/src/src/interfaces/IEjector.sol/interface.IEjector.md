# IEjector
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IEjector.sol)

**Inherits:**
[IExitTypes](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IExitTypes.sol/interface.IExitTypes.md)


## Functions
### PAUSE_ROLE


```solidity
function PAUSE_ROLE() external view returns (bytes32);
```

### RESUME_ROLE


```solidity
function RESUME_ROLE() external view returns (bytes32);
```

### RECOVERER_ROLE


```solidity
function RECOVERER_ROLE() external view returns (bytes32);
```

### STAKING_MODULE_ID


```solidity
function STAKING_MODULE_ID() external view returns (uint256);
```

### MODULE


```solidity
function MODULE() external view returns (ICSModule);
```

### STRIKES


```solidity
function STRIKES() external view returns (address);
```

### pauseFor

Pause ejection methods calls


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### resume

Resume ejection methods calls


```solidity
function resume() external;
```

### voluntaryEject

Withdraw the validator key from the Node Operator

Called by the node operator


```solidity
function voluntaryEject(uint256 nodeOperatorId, uint256 startFrom, uint256 keysCount, address refundRecipient)
    external
    payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`startFrom`|`uint256`|Index of the first key to withdraw|
|`keysCount`|`uint256`|Number of keys to withdraw|
|`refundRecipient`|`address`|Address to send the refund to|


### voluntaryEjectByArray

Withdraw the validator key from the Node Operator

Called by the node operator


```solidity
function voluntaryEjectByArray(uint256 nodeOperatorId, uint256[] calldata keyIndices, address refundRecipient)
    external
    payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndices`|`uint256[]`|Array of indices of the keys to withdraw|
|`refundRecipient`|`address`|Address to send the refund to|


### ejectBadPerformer

Eject Node Operator's key as a bad performer

Called by the `ValidatorStrikes` contract.
See `ValidatorStrikes.processBadPerformanceProof` to use this method permissionless


```solidity
function ejectBadPerformer(uint256 nodeOperatorId, uint256 keyIndex, address refundRecipient) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndex`|`uint256`|index of deposited key to eject|
|`refundRecipient`|`address`|Address to send the refund to|


### triggerableWithdrawalsGateway

TriggerableWithdrawalsGateway implementation used by the contract.


```solidity
function triggerableWithdrawalsGateway() external view returns (ITriggerableWithdrawalsGateway);
```

## Events
### VoluntaryEjectionRequested

```solidity
event VoluntaryEjectionRequested(uint256 indexed nodeOperatorId, bytes pubkey, address refundRecipient);
```

### BadPerformerEjectionRequested

```solidity
event BadPerformerEjectionRequested(uint256 indexed nodeOperatorId, bytes pubkey, address refundRecipient);
```

## Errors
### SigningKeysInvalidOffset

```solidity
error SigningKeysInvalidOffset();
```

### AlreadyWithdrawn

```solidity
error AlreadyWithdrawn();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroStrikesAddress

```solidity
error ZeroStrikesAddress();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

### SenderIsNotEligible

```solidity
error SenderIsNotEligible();
```

### SenderIsNotStrikes

```solidity
error SenderIsNotStrikes();
```

### NothingToEject

```solidity
error NothingToEject();
```

