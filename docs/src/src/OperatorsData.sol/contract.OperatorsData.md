# OperatorsData
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/OperatorsData.sol)

**Inherits:**
[IOperatorsData](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IOperatorsData.sol/interface.IOperatorsData.md), Initializable, AccessControlEnumerableUpgradeable

Operators metadata storage


## State Variables
### SETTER_ROLE

```solidity
bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE")
```


### _operators

```solidity
mapping(uint256 moduleId => mapping(uint256 id => OperatorInfo)) internal _operators
```


### _moduleAddresses

```solidity
mapping(uint256 moduleId => address moduleAddress) internal _moduleAddresses
```


### STAKING_ROUTER

```solidity
IStakingRouter public immutable STAKING_ROUTER
```


## Functions
### constructor


```solidity
constructor(address stakingRouter) ;
```

### initialize


```solidity
function initialize(address admin) external initializer;
```

### set

Set or update metadata for a Node Operator (callable by SETTER_ROLE)


```solidity
function set(uint256 moduleId, uint256 nodeOperatorId, OperatorInfo calldata info) external onlyRole(SETTER_ROLE);
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


### _resolveModuleAddress


```solidity
function _resolveModuleAddress(uint256 moduleId) internal returns (address module);
```

### _cacheModuleAddresses


```solidity
function _cacheModuleAddresses() internal;
```

### _nodeOperatorExists


```solidity
function _nodeOperatorExists(address module, uint256 nodeOperatorId) internal view returns (bool);
```

### _owner


```solidity
function _owner(address module, uint256 nodeOperatorId) internal view returns (address);
```

### _moduleExists


```solidity
function _moduleExists(uint256 moduleId) internal view;
```

### _validateModuleInterface


```solidity
function _validateModuleInterface(address module) internal view;
```

