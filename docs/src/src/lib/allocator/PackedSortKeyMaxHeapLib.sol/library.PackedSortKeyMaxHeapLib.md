# PackedSortKeyMaxHeapLib
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/allocator/PackedSortKeyMaxHeapLib.sol)

In-place max-heap helpers for `PackedSortKey[]`.

This is a memory-only priority queue primitive specialized for `PackedSortKey`.
`PackedSortKey` already encodes the full descending order as a single `uint256`,
so heap operations only need plain key comparisons to preserve both priority and tie-break rules.
A heap is represented as a flat array, but interpreted as a binary tree:
- node `i`
- left child `2 * i + 1`
- right child `2 * i + 2`
- parent `(i - 1) / 2`
Example array:
`[9, 5, 7, 1, 2]`
Tree view:
```text
9(0)
\
5(1)      7(2)
\
1(3)  2(4)
```
Heap property:
every parent is greater than or equal to its children.
This guarantees that the maximum key is always at index `0`.
`heapify` does not fully sort the array. It only rearranges it enough so that
repeated `popMax` calls return keys in descending order.
Expected complexity:
- `heapify`: O(n)
- `popMax`: O(log n)
- repeated extraction of `m` elements after `heapify`: O(n + m log n)


## Functions
### heapify

Reorders keys in place into a max-heap.

This is the standard bottom-up heap construction:
start from the last internal node and repeatedly sift it down until
every subtree satisfies the heap property.
Example:
`[2, 9, 7, 1, 5]`
becomes a valid max-heap such as:
`[9, 5, 7, 1, 2]`
Note that the result is not fully sorted. The only guarantee is that
the largest key is at the root and every subtree is itself a valid heap.


```solidity
function heapify(PackedSortKey[] memory heap) internal pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`heap`|`PackedSortKey[]`|Array to reinterpret as a max-heap.|


### popMax

Removes and returns the maximum key from a max-heap prefix.

The heap is assumed to occupy `heap[0:heapSize)`.
The operation is:
1. take the root at `heap[0]`
2. move the last active element to the root
3. sift the new root down until the heap property is restored
Example:
active heap `[9, 5, 7, 1, 2]`
- returned key: `9`
- move `2` to root -> `[2, 5, 7, 1, 2]`
- sift down -> `[7, 5, 2, 1, 2]`
After the call, callers are expected to shrink the active heap by one,
e.g. by decrementing `heapSize`.


```solidity
function popMax(PackedSortKey[] memory heap, uint256 heapSize) internal pure returns (PackedSortKey key);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`heap`|`PackedSortKey[]`|Heap array.|
|`heapSize`|`uint256`|Current heap size.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PackedSortKey`|Maximum key at the heap root.|


### _siftDown

Restores the heap property starting at `root` and moving toward the leaves.
The active heap occupies `heap[0:heapSize)`.
At each step:
- compare the current node with its children
- swap with the larger child if needed
- continue from the child's position
Example:
if the current subtree is:
```text
2
\
9   7
```
then `2` is swapped with `9`, because the parent must stay greater than
both children in a max-heap.


```solidity
function _siftDown(PackedSortKey[] memory heap, uint256 root, uint256 heapSize) private pure;
```

### _gt


```solidity
function _gt(PackedSortKey lhs, PackedSortKey rhs) private pure returns (bool);
```

