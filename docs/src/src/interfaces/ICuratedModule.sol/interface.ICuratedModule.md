# ICuratedModule
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/ICuratedModule.sol)

**Inherits:**
[IBaseModule](/src/interfaces/IBaseModule.sol/interface.IBaseModule.md), [IStakingModuleV2](/src/interfaces/IStakingModule.sol/interface.IStakingModuleV2.md)


## Functions
### initialize

Initializes the contract.


```solidity
function initialize(address admin) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|An address to grant the DEFAULT_ADMIN_ROLE to.|


### notifyNodeOperatorWeightChange

Notifies the module about the weight change of a node operator.


```solidity
function notifyNodeOperatorWeightChange(uint256 nodeOperatorId, uint256 oldWeight, uint256 newWeight) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`oldWeight`|`uint256`|The old weight of the node operator.|
|`newWeight`|`uint256`|The new weight of the node operator.|


### getOperatorWeights

Returns operator weights used for operator-level allocations in the module.

Provides weights from the on-chain allocation strategy used by the module.


```solidity
function getOperatorWeights(uint256[] calldata operatorIds) external view returns (uint256[] memory operatorWeights);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operatorIds`|`uint256[]`|Node operator IDs to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`operatorWeights`|`uint256[]`|Weights aligned with operatorIds.|


### getNodeOperatorWeightAndExternalStake

Returns effective weight and external stake for a node operator.

Reverts until the module deposit info cache is fully refreshed.


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


### getDepositAllocationTargets

Returns current deposit allocation targets for all operators.

Target = totalCurrent * operatorWeight / totalWeight (in validator count).
Includes operators regardless of depositable capacity for informational purposes.
Actual allocation recalculates shares only across operators with usable capacity,
so real per-operator amounts may differ from the targets shown here.
Arrays are indexed by operator id; zero-weight operators have zero values.


```solidity
function getDepositAllocationTargets()
    external
    view
    returns (uint256[] memory currentValidators, uint256[] memory targetValidators);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currentValidators`|`uint256[]`|Current active validator count per operator.|
|`targetValidators`|`uint256[]`|Target validator count per operator.|


### getTopUpAllocationTargets

Returns current top-up allocation targets for all operators.

`target = totalCurrent * operatorWeight / totalWeight` (in wei).
Includes operators regardless of top-up capacity for informational purposes.
Actual allocation recalculates shares only across operators with usable capacity,
so real per-operator amounts may differ from the targets shown here.
Arrays are indexed by operator id; zero-weight operators have zero values.


```solidity
function getTopUpAllocationTargets()
    external
    view
    returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currentAllocations`|`uint256[]`|Current operator stake in wei.|
|`targetAllocations`|`uint256[]`|Target operator stake in wei.|


### getDepositsAllocation

Method to get list of operators and amount of Eth that can be topped up to operator from depositAmount


```solidity
function getDepositsAllocation(uint256 depositAmount)
    external
    view
    returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositAmount`|`uint256`|Amount of Eth that can be deposited to module|


### META_REGISTRY

Returns current meta registry.


```solidity
function META_REGISTRY() external view returns (IMetaRegistry);
```

## Errors
### ZeroMetaRegistryAddress

```solidity
error ZeroMetaRegistryAddress();
```

### SenderIsNotMetaRegistry

```solidity
error SenderIsNotMetaRegistry();
```

