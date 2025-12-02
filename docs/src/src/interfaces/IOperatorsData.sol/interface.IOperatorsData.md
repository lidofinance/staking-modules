# IOperatorsData
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IOperatorsData.sol)


## Functions
### SETTER_ROLE


```solidity
function SETTER_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Role id allowed to set metadata|


### set

Set or update metadata for a Node Operator (callable by SETTER_ROLE)


```solidity
function set(uint256 moduleId, uint256 nodeOperatorId, OperatorInfo calldata info) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`|Module id|
|`nodeOperatorId`|`uint256`|Node Operator id|
|`info`|`OperatorInfo`|Metadata payload to persist|


### setByOwner

Set or update metadata by the Node Operator owner

Reverts if module does not support INodeOperatorOwner interface


```solidity
function setByOwner(uint256 moduleId, uint256 nodeOperatorId, string calldata name, string calldata description)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`|Module id|
|`nodeOperatorId`|`uint256`|Node Operator id|
|`name`|`string`|Display name|
|`description`|`string`|Long description|


### get

Get metadata for a Node Operator


```solidity
function get(uint256 moduleId, uint256 nodeOperatorId) external view returns (OperatorInfo memory info);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`|Module id|
|`nodeOperatorId`|`uint256`|Node Operator id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`info`|`OperatorInfo`|Stored metadata struct|


### isOwnerEditsRestricted

Check if owner metadata updates are restricted


```solidity
function isOwnerEditsRestricted(uint256 moduleId, uint256 nodeOperatorId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`|Module id|
|`nodeOperatorId`|`uint256`|Node Operator id|


## Events
### OperatorDataSet
Emitted when metadata is set for a Node Operator


```solidity
event OperatorDataSet(
    uint256 indexed moduleId,
    address module,
    uint256 indexed nodeOperatorId,
    string name,
    string description,
    bool ownerEditsRestricted
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`||
|`module`|`address`||
|`nodeOperatorId`|`uint256`|Id of the Node Operator|
|`name`|`string`|Display name|
|`description`|`string`|Long description|
|`ownerEditsRestricted`|`bool`|Whether owner updates are restricted|

### ModuleAddressCached
Emitted when a module address is cached


```solidity
event ModuleAddressCached(uint256 indexed moduleId, address moduleAddress);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`moduleId`|`uint256`|Module id|
|`moduleAddress`|`address`|Module address|

## Errors
### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### ZeroModuleId

```solidity
error ZeroModuleId();
```

### ZeroStakingRouterAddress

```solidity
error ZeroStakingRouterAddress();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

### SenderIsNotEligible

```solidity
error SenderIsNotEligible();
```

### OwnerEditsRestricted

```solidity
error OwnerEditsRestricted();
```

### UnknownModule

```solidity
error UnknownModule();
```

### ModuleDoesNotSupportNodeOperatorOwnerInterface

```solidity
error ModuleDoesNotSupportNodeOperatorOwnerInterface();
```

