# CuratedModule
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/CuratedModule.sol)

**Inherits:**
[ICuratedModule](/src/interfaces/ICuratedModule.sol/interface.ICuratedModule.md), [BaseModule](/src/abstract/BaseModule.sol/abstract.BaseModule.md)


## State Variables
### META_REGISTRY

```solidity
IMetaRegistry public immutable META_REGISTRY
```


## Functions
### constructor


```solidity
constructor(
    bytes32 moduleType,
    address lidoLocator,
    address parametersRegistry,
    address accounting,
    address exitPenalties,
    address metaRegistry
) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties);
```

### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(address admin) external override initializer;
```

### obtainDepositData

Obtains deposit data to be used by StakingRouter to deposit to the Ethereum Deposit
contract


```solidity
function obtainDepositData(
    uint256 depositsCount,
    bytes calldata depositCalldata // solhint-disable-line no-unused-vars
)
    external
    returns (bytes memory publicKeys, bytes memory signatures);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositsCount`|`uint256`|Number of deposits to be done|
|`depositCalldata`|`bytes`|Staking module defined data encoded as bytes. IMPORTANT: depositCalldata MUST NOT modify the deposit data set of the staking module|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`publicKeys`|`bytes`|Batch of the concatenated public validators keys|
|`signatures`|`bytes`|Batch of the concatenated deposit signatures for returned public keys|


### allocateDeposits

Validates that provided keys belong to the corresponding operators in the module and calculates deposit allocations for top-up

Reverts if any key doesn't belong to the module or data is invalid


```solidity
function allocateDeposits(
    uint256 maxDepositAmount,
    bytes[] calldata pubkeys,
    uint256[] calldata keyIndices,
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxDepositAmount`|`uint256`|Total ether amount available for top-up (must be multiple of 1 gwei)|
|`pubkeys`|`bytes[]`|List of validator public keys to top up|
|`keyIndices`|`uint256[]`|Indices of keys within their respective operators|
|`operatorIds`|`uint256[]`|Node operator IDs that own the keys|
|`topUpLimits`|`uint256[]`|Maximum amount that can be deposited per key based on CL data and SR internal logic.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocations`|`uint256[]`|Amount to deposit to each key|


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
function getOperatorWeights(uint256[] calldata operatorIds)
    external
    view
    returns (uint256[] memory operatorWeights);
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
function getDepositsAllocation(uint256 maxDepositAmount)
    external
    view
    returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxDepositAmount`|`uint256`||


### _updateDepositInfo


```solidity
function _updateDepositInfo(uint256 nodeOperatorId) internal override;
```

### _applyDepositableValidatorsCount


```solidity
function _applyDepositableValidatorsCount(
    NodeOperator storage no,
    uint256 nodeOperatorId,
    uint256 newCount,
    bool incrementNonceIfUpdated
) internal override returns (bool depositableChanged);
```

### _allocateTopUps


```solidity
function _allocateTopUps(
    uint256 maxDepositAmount,
    uint256[] calldata operatorIds,
    uint256[] calldata keyIndices,
    uint256[] memory topUpLimits
) internal returns (uint256[] memory allocations);
```

### _validateTopUpPublicKeys


```solidity
function _validateTopUpPublicKeys(
    bytes[] calldata pubkeys,
    uint256[] calldata keyIndices,
    uint256[] calldata operatorIds
) internal view;
```

### _metaRegistry


```solidity
function _metaRegistry() internal view returns (IMetaRegistry);
```

### _canRequestDepositInfoUpdate


```solidity
function _canRequestDepositInfoUpdate() internal view override;
```

