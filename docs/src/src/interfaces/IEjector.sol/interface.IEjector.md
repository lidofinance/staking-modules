# IEjector
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IEjector.sol)

**Inherits:**
[IExitTypes](/src/interfaces/IExitTypes.sol/interface.IExitTypes.md)


## Functions
### stakingModuleId


```solidity
function stakingModuleId() external view returns (uint256);
```

### MODULE


```solidity
function MODULE() external view returns (IBaseModule);
```

### STRIKES


```solidity
function STRIKES() external view returns (address);
```

### voluntaryEject

Request triggerable full withdrawals for Node Operator validator keys

Called by the node operator


```solidity
function voluntaryEject(uint256 nodeOperatorId, uint256[] calldata keyIndices, address refundRecipient)
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

### StakingModuleIdCached

```solidity
event StakingModuleIdCached(uint256 stakingModuleId);
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

### DuplicateKeyIndex

```solidity
error DuplicateKeyIndex();
```

### ZeroRefundRecipient

```solidity
error ZeroRefundRecipient();
```

### StakingModuleIdNotFound

```solidity
error StakingModuleIdNotFound();
```

