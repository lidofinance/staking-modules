# ICuratedModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/ICuratedModule.sol)

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


### changeNodeOperatorAddresses

Change both reward and manager addresses of a node operator.


```solidity
function changeNodeOperatorAddresses(uint256 nodeOperatorId, address newManagerAddress, address newRewardAddress)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newManagerAddress`|`address`|New manager address|
|`newRewardAddress`|`address`|New reward address|


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


### getNodeOperatorBalance

Returns stored operator balance (validators + pending).


```solidity
function getNodeOperatorBalance(uint256 operatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operatorId`|`uint256`|ID of the Node Operator|


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


### getDepositAllocationTargets

Returns current deposit allocation targets for all operators.

Target = totalCurrent * operatorWeight / totalWeight (in validator count).
Includes operators regardless of depositable capacity for informational purposes.
Actual allocation recalculates shares only across operators with available capacity,
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

Target = totalCurrent * operatorWeight / totalWeight (in wei).
Includes operators regardless of top-up capacity for informational purposes.
Actual allocation recalculates shares only across operators with available capacity,
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


### OPERATOR_ADDRESSES_ADMIN_ROLE


```solidity
function OPERATOR_ADDRESSES_ADMIN_ROLE() external view returns (bytes32);
```

### META_REGISTRY

Returns current meta registry.


```solidity
function META_REGISTRY() external view returns (IMetaRegistry);
```

## Events
### NodeOperatorBalanceUpdated

```solidity
event NodeOperatorBalanceUpdated(uint256 indexed operatorId, uint256 balanceWei);
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

### InvalidMaxCount

```solidity
error InvalidMaxCount();
```

### NodeOperatorWeightsUpdateInProgress

```solidity
error NodeOperatorWeightsUpdateInProgress();
```

