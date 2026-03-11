# IMetaRegistry
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IMetaRegistry.sol)

Meta registry for curated node operator groups.


## Functions
### MANAGE_OPERATOR_GROUPS_ROLE

Role allowed to manage operator groups.


```solidity
function MANAGE_OPERATOR_GROUPS_ROLE() external view returns (bytes32);
```

### NO_GROUP_ID

Sentinel value representing no operator group.


```solidity
function NO_GROUP_ID() external view returns (uint256);
```

### SET_OPERATOR_INFO_ROLE

Role allowed to set operator metadata.


```solidity
function SET_OPERATOR_INFO_ROLE() external view returns (bytes32);
```

### SET_BOND_CURVE_WEIGHT_ROLE

Role allowed to set bond curve weights.


```solidity
function SET_BOND_CURVE_WEIGHT_ROLE() external view returns (bytes32);
```

### MODULE

Curated module allowed to call module-only hooks.


```solidity
function MODULE() external view returns (ICuratedModule);
```

### ACCOUNTING

Accounting contract used for bond curve lookups.


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### initialize

Initialize the registry.


```solidity
function initialize(address admin) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address to receive DEFAULT_ADMIN_ROLE.|


### setOperatorMetadataAsAdmin

Set or update metadata for a node operator (callable by SET_OPERATOR_INFO_ROLE).


```solidity
function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external;
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


### createOrUpdateOperatorGroup

Create a new operator group or update an existing one.

Creating is allowed only when groupId == NO_GROUP_ID.


```solidity
function createOrUpdateOperatorGroup(uint256 groupId, OperatorGroup calldata groupInfo) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`groupId`|`uint256`|Group ID to update, or NO_GROUP_ID to create.|
|`groupInfo`|`OperatorGroup`|Group definition.|


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


### setBondCurveWeight

Set base weight for the bond curve ID (callable by SET_BOND_CURVE_WEIGHT_ROLE).

Effective weights for operators using the curve will not be updated automatically.
refreshOperatorWeight() must be called for the affected operators to update their effective weights.


```solidity
function setBondCurveWeight(uint256 curveId, uint256 weight) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve ID.|
|`weight`|`uint256`|Base allocation weight.|


### getNodeOperatorWeight

Returns effective weight for the node operator.

Returns 0 if the operator is not in a group.


```solidity
function getNodeOperatorWeight(uint256 nodeOperatorId) external view returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|Effective allocation weight.|


### getNodeOperatorWeightAndExternalStake

Returns effective weight and external stake for the node operator.

Returns (0, 0) if the operator is not in a group.


```solidity
function getNodeOperatorWeightAndExternalStake(uint256 nodeOperatorId)
    external
    view
    returns (uint256 weight, uint256 externalStake);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID to query.|

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


### refreshOperatorWeight

Trigger the operator weight update routine in the registry.


```solidity
function refreshOperatorWeight(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID to trigger the update for.|


## Events
### OperatorGroupCreated

```solidity
event OperatorGroupCreated(uint256 indexed groupId, OperatorGroup groupInfo);
```

### OperatorGroupUpdated

```solidity
event OperatorGroupUpdated(uint256 indexed groupId, OperatorGroup groupInfo);
```

### OperatorGroupCleared

```solidity
event OperatorGroupCleared(uint256 indexed groupId);
```

### BondCurveWeightSet

```solidity
event BondCurveWeightSet(uint256 indexed curveId, uint256 weight);
```

### OperatorMetadataSet

```solidity
event OperatorMetadataSet(uint256 indexed nodeOperatorId, OperatorMetadata metadata);
```

### NodeOperatorEffectiveWeightChanged

```solidity
event NodeOperatorEffectiveWeightChanged(uint256 indexed nodeOperatorId, uint256 oldWeight, uint256 newWeight);
```

## Errors
### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroAccountingAddress

```solidity
error ZeroAccountingAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### ZeroStakingRouterAddress

```solidity
error ZeroStakingRouterAddress();
```

### InvalidOperatorGroup

```solidity
error InvalidOperatorGroup();
```

### InvalidSubNodeOperatorShares

```solidity
error InvalidSubNodeOperatorShares();
```

### InvalidOperatorGroupId

```solidity
error InvalidOperatorGroupId();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

### NodeOperatorAlreadyInGroup

```solidity
error NodeOperatorAlreadyInGroup(uint256 nodeOperatorId);
```

### AlreadyUsedAsExternalOperator

```solidity
error AlreadyUsedAsExternalOperator();
```

### NodeOperatorNotInGroup

```solidity
error NodeOperatorNotInGroup();
```

### SenderIsNotModule

```solidity
error SenderIsNotModule();
```

### SenderIsNotEligible

```solidity
error SenderIsNotEligible();
```

### OwnerEditsRestricted

```solidity
error OwnerEditsRestricted();
```

### UnsupportedExternalOperatorType

```solidity
error UnsupportedExternalOperatorType();
```

### SameBondCurveWeight

```solidity
error SameBondCurveWeight();
```

### ModuleAddressNotCached

```solidity
error ModuleAddressNotCached();
```

### OperatorNameTooLong

```solidity
error OperatorNameTooLong();
```

### OperatorDescriptionTooLong

```solidity
error OperatorDescriptionTooLong();
```

## Structs
### SubNodeOperator

```solidity
struct SubNodeOperator {
    uint64 nodeOperatorId;
    uint16 share;
}
```

### ExternalOperator

```solidity
struct ExternalOperator {
    bytes data;
}
```

### OperatorGroup

```solidity
struct OperatorGroup {
    SubNodeOperator[] subNodeOperators;
    ExternalOperator[] externalOperators;
}
```

