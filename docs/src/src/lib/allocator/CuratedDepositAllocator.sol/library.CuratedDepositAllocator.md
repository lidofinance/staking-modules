# CuratedDepositAllocator
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/allocator/CuratedDepositAllocator.sol)

Curated deposit allocation helpers (external library for bytecode savings).

Invariants assumed by this library:
- totalWithdrawnKeys <= totalDepositedKeys per operator.
- each operatorId < operatorsCount.


## State Variables
### MAX_EFFECTIVE_BALANCE

```solidity
uint256 public constant MAX_EFFECTIVE_BALANCE = 2048 ether
```


### MIN_ACTIVATION_BALANCE

```solidity
uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether
```


### DEPOSIT_STEP

```solidity
uint256 internal constant DEPOSIT_STEP = 1
```


### TOP_UP_STEP

```solidity
uint256 internal constant TOP_UP_STEP = 2 ether
```


## Functions
### allocateInitialDeposits

Allocate new validator deposits across curated operators.

Input preparation and iteration behavior:
- Only operators with capacity > 0 and non-zero allocation weight are included.
- Current amounts are derived from deposited minus withdrawn keys (active keys).
- Operators that hit their capacity here will have capacity == 0 next call and
will be excluded; remaining operators’ shares increase.

Returns compact arrays containing only operators with non-zero allocations.


```solidity
function allocateInitialDeposits(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 operatorsCount,
    uint256 depositsCount
) external view returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`|Node operator storage mapping from the module.|
|`operatorsCount`|`uint256`|Total operators count in the module.|
|`depositsCount`|`uint256`|Number of validator deposits to allocate.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocated`|`uint256`|Number of deposits actually allocated.|
|`operatorIds`|`uint256[]`|Operator ids for allocated operators.|
|`allocations`|`uint256[]`|Per-operator allocations aligned to operatorIds.|


### allocateTopUps

Allocate top-up deposit amount across curated operators.

Input preparation and iteration behavior:
- Duplicated operator ids are not expected (caller guarantees uniqueness).
- Only operators with non-zero allocation weight are included.
- Shares are computed across all eligible operators in the module
(non-zero weight, non-zero top-up capacity),
so a subset cannot bias its share by omitting other eligible operators.
- Per-operator capacity is computed as:
`(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
- Per-key top-up limits are *not* used as caps for allocation; they are
applied later per-key and may leave unallocated remainder.
- Operators that have zero remaining balance after allocation are excluded
on later iterations by capacity == 0 at the module level.


```solidity
function allocateTopUps(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    mapping(uint256 => uint256) storage nodeOperatorBalances,
    uint256 operatorsCount,
    uint256 allocationAmount,
    uint256[] calldata operatorIds
) external view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`|Node operator storage mapping from the module.|
|`nodeOperatorBalances`|`mapping(uint256 => uint256)`|Per-operator balance (in wei) storage mapping from the module.|
|`operatorsCount`|`uint256`|Total operators count in the module.|
|`allocationAmount`|`uint256`|Total top-up amount in wei to allocate.|
|`operatorIds`|`uint256[]`|Key owner operator ids for this top-up request.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocated`|`uint256`|Total allocated amount in wei.|
|`allocatedOperatorIds`|`uint256[]`|Operator ids for allocated operators.|
|`allocations`|`uint256[]`|Per-operator allocations aligned to allocatedOperatorIds.|


### _collectDepositableOperatorsData

Collect eligible operators for deposit allocation.
Filters out zero capacity and zero-weight operators.


```solidity
function _collectDepositableOperatorsData(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 operatorsCount
) internal view returns (DepositableOperatorsData memory data);
```

### _collectTopUpEligibleOperatorsData

Collect eligible operators for top-up allocation.
Duplicates in operatorIds are disallowed and must be filtered by the caller.


```solidity
function _collectTopUpEligibleOperatorsData(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    mapping(uint256 => uint256) storage nodeOperatorBalances,
    uint256 operatorsCount,
    uint256[] calldata operatorIds
) internal view returns (DepositableOperatorsData memory data);
```

### _collectTopUpGlobalBaseline


```solidity
function _collectTopUpGlobalBaseline(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    mapping(uint256 => uint256) storage nodeOperatorBalances,
    uint256 operatorsCount
)
    internal
    view
    returns (
        uint256 weightSum,
        uint256 totalCurrent,
        uint256[] memory weightsByOperatorId,
        uint256[] memory capacitiesByOperatorId,
        uint256[] memory currentStakeByOperatorId
    );
```

### _topUpCapacity

Maximum top-up capacity for an operator:
(active validators * 2048 ETH) - current balance, floored at zero.


```solidity
function _topUpCapacity(NodeOperator storage no, uint256 balanceWei) internal view returns (uint256 capacity);
```

### getDepositAllocationTargets

Returns current deposit allocation targets for all operators.

Target = totalCurrent * operatorWeight / totalWeight (in validator count).
Includes operators regardless of depositable capacity for informational purposes.
Actual allocation recalculates shares only across operators with available capacity,
so real per-operator amounts may differ from the targets shown here.
Arrays are indexed by operator id; zero-weight operators have zero values.


```solidity
function getDepositAllocationTargets(mapping(uint256 => NodeOperator) storage nodeOperators, uint256 operatorsCount)
    external
    view
    returns (uint256[] memory currentValidators, uint256[] memory targetValidators);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`|Node operator storage mapping from the module.|
|`operatorsCount`|`uint256`|Total operators count in the module.|

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
function getTopUpAllocationTargets(mapping(uint256 => uint256) storage nodeOperatorBalances, uint256 operatorsCount)
    external
    view
    returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorBalances`|`mapping(uint256 => uint256)`|Per-operator balance (in wei) storage mapping from the module.|
|`operatorsCount`|`uint256`|Total operators count in the module.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currentAllocations`|`uint256[]`|Current operator stake in wei.|
|`targetAllocations`|`uint256[]`|Target operator stake in wei.|


### quantizeForTopUp

Quantizes a value down to the nearest multiple of TOP_UP_STEP.


```solidity
function quantizeForTopUp(uint256 value) internal pure returns (uint256);
```

### _computeAllocations

Normalizes raw weights into X96 shares and runs the allocator in-memory.
Expects operatorsData arrays already filtered/truncated to eligible operators.


```solidity
function _computeAllocations(DepositableOperatorsData memory operatorsData, uint256 step, uint256 allocationAmount)
    internal
    pure
    returns (uint256 allocated, uint256[] memory allocations);
```

### _compactAllocations


```solidity
function _compactAllocations(uint256[] memory operatorIds, uint256[] memory eligibleAllocations, uint256 count)
    internal
    pure
    returns (uint256[] memory compactIds, uint256[] memory allocations);
```

### _normalizeWeightsToShares

Converts raw weights in alloc.sharesX96 to X96-scaled shares in-place.


```solidity
function _normalizeWeightsToShares(DepositableOperatorsData memory data) internal pure;
```

### _truncateDepositable

Shrinks eligible arrays to the collected eligible count.


```solidity
function _truncateDepositable(DepositableOperatorsData memory data) internal pure;
```

## Structs
### DepositableOperatorsData

```solidity
struct DepositableOperatorsData {
    // Shared allocation arrays + totalCurrent — passed directly to the allocator.
    // During collection, alloc.sharesX96 temporarily stores raw weights
    // and is normalized in-place right before allocation.
    AllocationState alloc;
    uint256[] operatorIds; // Operator ids aligned with arrays above (compacted to operators included in allocation).
    uint256 count; // Number of operators included in allocation (filled entries in the arrays above).
    uint256 weightSum; // Sum of weights across eligible operators (for share calculation).
}
```

