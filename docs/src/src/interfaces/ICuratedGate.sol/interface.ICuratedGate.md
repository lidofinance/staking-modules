# ICuratedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/ICuratedGate.sol)

**Inherits:**
[IMerkleGate](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IMerkleGate.sol/interface.IMerkleGate.md)

Allows eligible addresses to create Node Operators and store metadata.


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

### MODULE


```solidity
function MODULE() external view returns (ICuratedModule);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ICuratedModule`|MODULE Curated module reference|


### MODULE_ID


```solidity
function MODULE_ID() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|MODULE_ID Curated module id cached for OperatorsData integration|


### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IAccounting`|ACCOUNTING Accounting reference|


### OPERATORS_DATA


```solidity
function OPERATORS_DATA() external view returns (IOperatorsData);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IOperatorsData`|OPERATORS_DATA Operators metadata storage reference|


### curveId


```solidity
function curveId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|curveId Instance-specific custom curve id|


### pauseFor

Pause the gate for a given duration


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration in seconds|


### resume

Resume the gate


```solidity
function resume() external;
```

### createNodeOperator

Create an empty Node Operator for the caller if eligible.
Stores provided name/description in OperatorsData. Marks caller as consumed.


```solidity
function createNodeOperator(
    string calldata name,
    string calldata description,
    address managerAddress,
    address rewardAddress,
    bytes32[] calldata proof
) external returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|Display name of the Node Operator|
|`description`|`string`|Description of the Node Operator|
|`managerAddress`|`address`|Address to set as manager; if zero, defaults will be used by the module|
|`rewardAddress`|`address`|Address to set as rewards receiver; if zero, defaults will be used by the module|
|`proof`|`bytes32[]`|Merkle proof for the caller address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Newly created Node Operator id|


## Errors
### InvalidCurveId
Errors


```solidity
error InvalidCurveId();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroModuleId

```solidity
error ZeroModuleId();
```

### ZeroOperatorsDataAddress

```solidity
error ZeroOperatorsDataAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

