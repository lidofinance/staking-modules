# CuratedDepositAllocator
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/allocator/CuratedDepositAllocator.sol)

Curated deposit allocation helpers.

External deployment-linked library used by CuratedModule for bytecode savings.
Invariants assumed by this library:
- totalWithdrawnKeys <= totalDepositedKeys per operator.
- each operatorId < operatorsCount.


## State Variables
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

Returns operator-level top-up allocations for the provided operators.
- Duplicated operator ids are not expected (caller guarantees uniqueness).
- Only operators with non-zero allocation weight and usable top-up capacity are included.
- Shares are computed across all eligible operators in the module
(non-zero weight, non-zero quantized top-up capacity),
so a subset cannot bias its share by omitting other eligible operators.
- Per-operator capacity is computed as:
`(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
- `current_operator_balance` here is the module's tracked stake view, not a live decrementing oracle value:
active balance decreases are intentionally reflected later via withdrawal reporting.


```solidity
function allocateTopUps(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 allocationAmount,
    uint256[] calldata operatorIds
) external view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`$`|`ModuleLinearStorage.BaseModuleStorage`|Base module storage pointer.|
|`allocationAmount`|`uint256`|Total top-up amount in wei to allocate.|
|`operatorIds`|`uint256[]`|Unique operator ids to include in allocation.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocated`|`uint256`|Total allocated amount in wei.|
|`allocatedOperatorIds`|`uint256[]`|Operator ids for allocated operators.|
|`allocations`|`uint256[]`|Per-operator allocations aligned to allocatedOperatorIds.|


### allocateAndDistributeTopUps

Allocate top-ups across unique operators and immediately distribute them to keys.
- Raw operator ids may contain duplicates; they are deduplicated before operator-level allocation
to avoid overweighting operators that appear on multiple requested keys.
- Shares are computed across all eligible operators in the module
(non-zero weight, non-zero quantized top-up capacity),
so a subset cannot bias its share by omitting other eligible operators.
- Per-operator capacity is computed as:
`(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
- `current_operator_balance` is intentionally based on tracked stake that preserves prior observed highs
until withdrawal settlement, so active slashing/leakage is accounted when penalties are finalized.
- Per-key top-up limits are not used as caps for operator-level allocation; they are
applied during key-level distribution and may leave unallocated remainder.


```solidity
function allocateAndDistributeTopUps(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 allocationAmount,
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory allocations);
```

### _uniqueOperatorIds


```solidity
function _uniqueOperatorIds(uint256[] calldata operatorIds) private returns (uint256[] memory uniqueOperatorIds);
```

### _allocateTopUps


```solidity
function _allocateTopUps(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256 allocationAmount,
    uint256[] memory operatorIds
) private view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations);
```

### _collectDepositableOperatorsData

Collect eligible operators for deposit allocation.
Filters out zero capacity and zero-weight operators.


```solidity
function _collectDepositableOperatorsData(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 operatorsCount
) private view returns (DepositableOperatorsData memory data);
```

### _collectTopUpEligibleOperatorsData

Collect eligible operators for top-up allocation.
Duplicates in operatorIds are disallowed and must be filtered by the caller.


```solidity
function _collectTopUpEligibleOperatorsData(
    ModuleLinearStorage.BaseModuleStorage storage $,
    uint256[] memory operatorIds
) private view returns (DepositableOperatorsData memory data);
```

### _collectTopUpGlobalBaseline


```solidity
function _collectTopUpGlobalBaseline(ModuleLinearStorage.BaseModuleStorage storage $)
    private
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
Actual allocation recalculates shares only across operators with usable capacity,
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
Actual allocation recalculates shares only across operators with usable capacity,
so real per-operator amounts may differ from the targets shown here.
Arrays are indexed by operator id; zero-weight operators have zero values.


```solidity
function getTopUpAllocationTargets(ModuleLinearStorage.BaseModuleStorage storage $)
    external
    view
    returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`$`|`ModuleLinearStorage.BaseModuleStorage`|Base module storage pointer.|

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

### _distributeAllocationsWithinLimits


```solidity
function _distributeAllocationsWithinLimits(
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits,
    uint256[] memory allocatedOperatorIds,
    uint256[] memory remainingOperatorAllocations
) private returns (uint256[] memory allocations);
```

### _computeAllocations

Normalizes raw weights into X96 shares and runs the allocator in-memory.
Expects operatorsData arrays already filtered/truncated to eligible operators.


```solidity
function _computeAllocations(DepositableOperatorsData memory operatorsData, uint256 step, uint256 allocationAmount)
    private
    pure
    returns (uint256 allocated, uint256[] memory allocations);
```

### _compactAllocations


```solidity
function _compactAllocations(uint256[] memory operatorIds, uint256[] memory eligibleAllocations, uint256 count)
    private
    pure
    returns (uint256[] memory compactIds, uint256[] memory allocations);
```

### _normalizeWeightsToShares

Converts raw weights in alloc.sharesX96 to X96-scaled shares in-place.


```solidity
function _normalizeWeightsToShares(DepositableOperatorsData memory data) private pure;
```

### _truncateDepositable

Shrinks eligible arrays to the collected eligible count.


```solidity
function _truncateDepositable(DepositableOperatorsData memory data) private pure;
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

