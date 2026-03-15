# MetaRegistry
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/MetaRegistry.sol)

**Inherits:**
[IMetaRegistry](/src/interfaces/IMetaRegistry.sol/interface.IMetaRegistry.md), Initializable, AccessControlEnumerableUpgradeable

Stores meta-operator group definitions for the curated module.


## State Variables
### MANAGE_OPERATOR_GROUPS_ROLE

```solidity
bytes32 public constant MANAGE_OPERATOR_GROUPS_ROLE = keccak256("MANAGE_OPERATOR_GROUPS_ROLE")
```


### SET_OPERATOR_INFO_ROLE

```solidity
bytes32 public constant SET_OPERATOR_INFO_ROLE = keccak256("SET_OPERATOR_INFO_ROLE")
```


### SET_BOND_CURVE_WEIGHT_ROLE

```solidity
bytes32 public constant SET_BOND_CURVE_WEIGHT_ROLE = keccak256("SET_BOND_CURVE_WEIGHT_ROLE")
```


### NO_GROUP_ID

```solidity
uint256 public constant NO_GROUP_ID = 0
```


### MODULE

```solidity
ICuratedModule public immutable MODULE
```


### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### STAKING_ROUTER

```solidity
IStakingRouter public immutable STAKING_ROUTER
```


### MAX_BP

```solidity
uint256 internal constant MAX_BP = 10000
```


### EXTERNAL_STAKE_PER_VALIDATOR

```solidity
uint256 internal constant EXTERNAL_STAKE_PER_VALIDATOR = 32 ether
```


### META_REGISTRY_STORAGE_LOCATION

```solidity
bytes32 private constant META_REGISTRY_STORAGE_LOCATION =
    0xa7ec41e1a061c67796a04fcd9cc7cab9545b0a750beebc54139d9ed9d2251c00
```


## Functions
### constructor


```solidity
constructor(address module) ;
```

### initialize

Initialize the registry.


```solidity
function initialize(address admin) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address to receive DEFAULT_ADMIN_ROLE.|


### setOperatorMetadataAsAdmin

Set or update metadata for a node operator (callable by SET_OPERATOR_INFO_ROLE).


```solidity
function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata)
    external
    onlyRole(SET_OPERATOR_INFO_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID.|
|`metadata`|`OperatorMetadata`|Metadata payload to persist.|


### setOperatorMetadataAsOwner

Set or update metadata by the node operator owner.

Reverts if module does not support IBaseModule interface.


```solidity
function setOperatorMetadataAsOwner(uint256 nodeOperatorId, string calldata name, string calldata description)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID.|
|`name`|`string`|Display name.|
|`description`|`string`|Long description.|


### createOrUpdateOperatorGroup

Create a new operator group or update an existing one.

Creating is allowed only when groupId == NO_GROUP_ID.


```solidity
function createOrUpdateOperatorGroup(uint256 groupId, OperatorGroup calldata groupInfo)
    external
    onlyRole(MANAGE_OPERATOR_GROUPS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`groupId`|`uint256`|Group ID to update, or NO_GROUP_ID to create.|
|`groupInfo`|`OperatorGroup`|Group definition.|


### setBondCurveWeight

Set base weight for the bond curve ID (callable by SET_BOND_CURVE_WEIGHT_ROLE).

Effective weights for operators using the curve will not be updated automatically.
refreshOperatorWeight() must be called for the affected operators to update their effective weights.


```solidity
function setBondCurveWeight(uint256 curveId, uint256 weight) external onlyRole(SET_BOND_CURVE_WEIGHT_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve ID.|
|`weight`|`uint256`|Base allocation weight.|


### refreshOperatorWeight

Trigger the operator weight update routine in the registry.


```solidity
function refreshOperatorWeight(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID to trigger the update for.|


### getOperatorMetadata

Get metadata for a node operator.


```solidity
function getOperatorMetadata(uint256 nodeOperatorId) external view returns (OperatorMetadata memory metadata);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`metadata`|`OperatorMetadata`|Stored metadata struct.|


### getOperatorGroup

Fetch an operator group by ID.


```solidity
function getOperatorGroup(uint256 groupId) external view returns (OperatorGroup memory groupInfo);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`groupId`|`uint256`|Group ID to fetch.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`groupInfo`|`OperatorGroup`|Group definition.|


### getOperatorGroupsCount

Returns total operator groups count.


```solidity
function getOperatorGroupsCount() external view returns (uint256 count);
```

### getNodeOperatorGroupId

Get Node Operator group ID (returns NO_GROUP_ID if the operator is not in any group).


```solidity
function getNodeOperatorGroupId(uint256 nodeOperatorId) external view returns (uint256 operatorGroupId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`operatorGroupId`|`uint256`|Group ID.|


### getExternalOperatorGroupId

Get External Operator group ID (returns NO_GROUP_ID if the operator is not in any group).


```solidity
function getExternalOperatorGroupId(ExternalOperator calldata op) external view returns (uint256 operatorGroupId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`op`|`ExternalOperator`|External operator.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`operatorGroupId`|`uint256`|Group ID.|


### getBondCurveWeight

Returns base weight for the bond curve ID.


```solidity
function getBondCurveWeight(uint256 curveId) external view returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|Base allocation weight.|


### getNodeOperatorWeight

Returns effective weight for the node operator.

Returns 0 if the operator is not in a group.


```solidity
function getNodeOperatorWeight(uint256 noId) external view returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`noId`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|Effective allocation weight.|


### getNodeOperatorWeightAndExternalStake

Returns effective weight and external stake for the node operator.

Returns (0, 0) if the operator is not in a group.


```solidity
function getNodeOperatorWeightAndExternalStake(uint256 noId)
    external
    view
    returns (uint256 weight, uint256 externalStake);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`noId`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|Effective allocation weight.|
|`externalStake`|`uint256`|External stake amount in wei.|


### getOperatorWeights

Returns allocation weights for the given node operators.


```solidity
function getOperatorWeights(uint256[] calldata nodeOperatorIds)
    external
    view
    returns (uint256[] memory operatorWeights);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`uint256[]`|Node operator IDs to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`operatorWeights`|`uint256[]`|Weights aligned with nodeOperatorIds.|


### _createGroup


```solidity
function _createGroup(OperatorGroup calldata groupInfo) internal;
```

### _updateGroup


```solidity
function _updateGroup(uint256 groupId, OperatorGroup calldata groupInfo) internal;
```

### _resetGroup


```solidity
function _resetGroup(uint256 groupId) internal;
```

### _storeSubOperators


```solidity
function _storeSubOperators(uint256 groupId, SubNodeOperator[] calldata subNodeOperators) internal;
```

### _storeExternalOperators


```solidity
function _storeExternalOperators(uint256 groupId, ExternalOperator[] calldata externalOperators) internal;
```

### _refreshOperatorWeight

`noId` should be a part of group with `groupId`.


```solidity
function _refreshOperatorWeight(uint256 groupId, uint256 noId) internal;
```

### _setEffectiveWeight


```solidity
function _setEffectiveWeight(uint256 nodeOperatorId, uint256 newWeight) internal returns (uint256 oldWeight);
```

### _storeOperatorMetadata


```solidity
function _storeOperatorMetadata(uint256 nodeOperatorId, OperatorMetadata memory metadata) internal;
```

### _checkExternalOperatorExistsTypeNOR


```solidity
function _checkExternalOperatorExistsTypeNOR(ExternalOperator memory op) internal;
```

### _getOrCacheModuleAddress

Returns the module address for `moduleId`, resolving from
STAKING_ROUTER on cache miss.


```solidity
function _getOrCacheModuleAddress(uint8 moduleId) internal returns (address addr);
```

### _getLatestEffectiveWeight


```solidity
function _getLatestEffectiveWeight(uint256 nodeOperatorId, uint256 share) internal view returns (uint256);
```

### _getOperatorBaseWeight


```solidity
function _getOperatorBaseWeight(uint256 nodeOperatorId) internal view returns (uint256);
```

### _getCachedModuleAddress

Returns the cached module address. Reverts if the address was
never resolved via `_getOrCacheModuleAddress`.


```solidity
function _getCachedModuleAddress(uint8 moduleId) internal view returns (address addr);
```

### _onlyExistingOperator


```solidity
function _onlyExistingOperator(address module, uint256 nodeOperatorId) internal view;
```

### _nodeOperatorExists


```solidity
function _nodeOperatorExists(address module, uint256 nodeOperatorId) internal view returns (bool);
```

### _nodeOperatorOwner


```solidity
function _nodeOperatorOwner(address module, uint256 nodeOperatorId) internal view returns (address);
```

### _totalExternalStake


```solidity
function _totalExternalStake(ExternalOperator[] storage externalOperators)
    internal
    view
    returns (uint256 totalExternalStake);
```

### _getOperatorExternalStakeTypeNOR


```solidity
function _getOperatorExternalStakeTypeNOR(ExternalOperator memory op) internal view returns (uint256 stake);
```

### _storage


```solidity
function _storage() internal pure returns (MetaRegistryStorage storage $);
```

## Structs
### CachedOperatorGroup

```solidity
struct CachedOperatorGroup {
    uint64[] subNodeOperatorIds;
    ExternalOperator[] externalOperators;
}
```

### GroupIndex

```solidity
struct GroupIndex {
    mapping(uint256 nodeOperatorId => uint256 groupId) groupIdByOperatorId;
    mapping(bytes32 externalKey => uint256 groupId) groupIdByExternalKey;
    mapping(uint256 nodeOperatorId => uint16 share) shareByOperatorId;
}
```

### EffectiveWeightCache

```solidity
struct EffectiveWeightCache {
    mapping(uint256 nodeOperatorId => uint256 weight) operatorEffectiveWeight;
    mapping(uint256 groupId => uint256 weight) groupEffectiveWeightSum;
}
```

### MetaRegistryStorage
**Note:**
storage-location: erc7201:MetaRegistry


```solidity
struct MetaRegistryStorage {
    mapping(uint256 curveId => uint256 weight) bondCurveWeight;
    CachedOperatorGroup[] groups;
    GroupIndex groupIndex;
    EffectiveWeightCache effectiveWeightCache;
    mapping(uint256 nodeOperatorId => OperatorMetadata) operatorMetadata;
    mapping(uint256 moduleId => address moduleAddress) moduleAddressCache;
}
```

