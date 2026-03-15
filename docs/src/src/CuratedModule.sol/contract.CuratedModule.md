# CuratedModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/CuratedModule.sol)

**Inherits:**
[ICuratedModule](/src/interfaces/ICuratedModule.sol/interface.ICuratedModule.md), [BaseModule](/src/abstract/BaseModule.sol/abstract.BaseModule.md)


## State Variables
### OPERATOR_ADDRESSES_ADMIN_ROLE

```solidity
bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE = keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE")
```


### META_REGISTRY

```solidity
IMetaRegistry public immutable META_REGISTRY
```


### CURATED_MODULE_STORAGE_LOCATION

```solidity
bytes32 private constant CURATED_MODULE_STORAGE_LOCATION =
    0x748416948424a2a643c796b7b8213bcf41155fd3a072f0851ad0a3d6ca632500
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
    bytes calldata /* depositCalldata */
)
    external
    returns (bytes memory publicKeys, bytes memory signatures);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositsCount`|`uint256`|Number of deposits to be done|
|`<none>`|`bytes`||

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


### updateOperatorBalances

Called by StakingRouter to update node operator total balances.

Total balances are denominated in gwei.


```solidity
function updateOperatorBalances(bytes calldata operatorIds, bytes calldata totalBalancesGwei) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operatorIds`|`bytes`|Bytes packed array of node operator IDs.|
|`totalBalancesGwei`|`bytes`|Bytes packed array of total balances (validators + pending), in gwei.|


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


### getNodeOperatorBalance

Returns stored operator balance (validators + pending).


```solidity
function getNodeOperatorBalance(uint256 operatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operatorId`|`uint256`|ID of the Node Operator|


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

### _uniqueOperatorIds

Deduplicate operator ids for allocation to avoid overweighting by repeated keys.


```solidity
function _uniqueOperatorIds(uint256[] calldata operatorIds) internal returns (uint256[] memory uniqueOperatorIds);
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

### _curatedStorage


```solidity
function _curatedStorage() internal pure returns (CuratedModuleStorage storage $);
```

## Structs
### CuratedModuleStorage
**Note:**
storage-location: erc7201:CuratedModule


```solidity
struct CuratedModuleStorage {
    // Tracks per-operator balances (in wei) reported by the Accounting oracle.
    mapping(uint256 nodeOperatorId => uint256 balance) operatorBalances;
}
```

