# Ejector
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/Ejector.sol)

**Inherits:**
[IEjector](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IEjector.sol/interface.IEjector.md), [ExitTypes](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/ExitTypes.sol/abstract.ExitTypes.md), AccessControlEnumerable, [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)


## State Variables
### PAUSE_ROLE

```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE

```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


### RECOVERER_ROLE

```solidity
bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE")
```


### STAKING_MODULE_ID

```solidity
uint256 public immutable STAKING_MODULE_ID
```


### MODULE

```solidity
ICSModule public immutable MODULE
```


### STRIKES

```solidity
address public immutable STRIKES
```


## Functions
### onlyStrikes


```solidity
modifier onlyStrikes() ;
```

### constructor


```solidity
constructor(address module, address strikes, uint256 stakingModuleId, address admin) ;
```

### resume

Resume ejection methods calls


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause ejection methods calls


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### voluntaryEject

Withdraw the validator key from the Node Operator


```solidity
function voluntaryEject(uint256 nodeOperatorId, uint256 startFrom, uint256 keysCount, address refundRecipient)
    external
    payable
    whenResumed;
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

Additional method for non-sequential keys to save gas and decrease fee amount compared
to separate transactions.


```solidity
function voluntaryEjectByArray(uint256 nodeOperatorId, uint256[] calldata keyIndices, address refundRecipient)
    external
    payable
    whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndices`|`uint256[]`|Array of indices of the keys to withdraw|
|`refundRecipient`|`address`|Address to send the refund to|


### ejectBadPerformer

Eject Node Operator's key as a bad performer


```solidity
function ejectBadPerformer(uint256 nodeOperatorId, uint256 keyIndex, address refundRecipient)
    external
    payable
    whenResumed
    onlyStrikes;
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
function triggerableWithdrawalsGateway() public view returns (ITriggerableWithdrawalsGateway);
```

### _onlyStrikes


```solidity
function _onlyStrikes() internal view;
```

### _onlyNodeOperatorOwner

Verifies that the sender is the owner of the node operator


```solidity
function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

