# IMerkleGate
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IMerkleGate.sol)

**Inherits:**
[INamedUpgradeable](/src/interfaces/INamedUpgradeable.sol/interface.INamedUpgradeable.md)

**Title:**
Merkle Gate Interface

Common surface for gates that guard node operator creation via Merkle proofs.


## Functions
### SET_TREE_ROLE


```solidity
function SET_TREE_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|role required to update tree parameters|


### treeRoot


```solidity
function treeRoot() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Current Merkle tree root|


### treeCid


```solidity
function treeCid() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Current Merkle tree CID|


### curveId


```solidity
function curveId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Instance-specific bond curve id|


### setTreeParams

Update Merkle tree params


```solidity
function setTreeParams(bytes32 treeRoot_, string calldata treeCid_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`treeRoot_`|`bytes32`|New root|
|`treeCid_`|`string`|New CID|


### isConsumed

Returns whether a member already consumed eligibility


```solidity
function isConsumed(address member) external view returns (bool);
```

### verifyProof

Verify proof for a member against current tree


```solidity
function verifyProof(address member, bytes32[] calldata proof) external view returns (bool);
```

### hashLeaf

Hash leaf encoding for addresses in the Merkle tree


```solidity
function hashLeaf(address member) external pure returns (bytes32);
```

### initialize

Initialize the gate instance.


```solidity
function initialize(uint256 curveId, bytes32 treeRoot, string calldata treeCid, string calldata name, address admin)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve id used by the gate.|
|`treeRoot`|`bytes32`|Initial Merkle tree root.|
|`treeCid`|`string`|Initial Merkle tree CID.|
|`name`|`string`|Human-readable gate name.|
|`admin`|`address`|Address to be granted DEFAULT_ADMIN_ROLE.|


### getInitializedVersion

Initialized version for upgradeable tooling


```solidity
function getInitializedVersion() external view returns (uint64);
```

## Events
### TreeSet
Emitted when a new Merkle tree is set


```solidity
event TreeSet(bytes32 indexed treeRoot, string treeCid);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`treeRoot`|`bytes32`|Root of the Merkle tree|
|`treeCid`|`string`|CID of the Merkle tree|

### Consumed
Emitted when a member consumes eligibility


```solidity
event Consumed(address indexed member);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`member`|`address`|Address that consumed eligibility|

## Errors
### InvalidProof
Errors


```solidity
error InvalidProof();
```

### AlreadyConsumed

```solidity
error AlreadyConsumed();
```

### InvalidTreeRoot

```solidity
error InvalidTreeRoot();
```

### InvalidTreeCid

```solidity
error InvalidTreeCid();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

