# MerkleGate
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/abstract/MerkleGate.sol)

**Inherits:**
[IMerkleGate](/src/interfaces/IMerkleGate.sol/interface.IMerkleGate.md), [NamedUpgradeable](/src/abstract/NamedUpgradeable.sol/abstract.NamedUpgradeable.md), AccessControlEnumerableUpgradeable, [PausableWithRoles](/src/abstract/PausableWithRoles.sol/abstract.PausableWithRoles.md), [AssetRecoverer](/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)

Shared Merkle-based gate logic for gated node-operator flows.


## State Variables
### SET_TREE_ROLE

```solidity
bytes32 public constant SET_TREE_ROLE = keccak256("SET_TREE_ROLE")
```


### curveId
Id of the bond curve to be assigned for eligible members.


```solidity
uint256 public curveId
```


### treeRoot

```solidity
bytes32 public treeRoot
```


### treeCid

```solidity
string public treeCid
```


### _consumedAddresses
Tracks whether an address already consumed its eligibility.


```solidity
mapping(address => bool) internal _consumedAddresses
```


## Functions
### setTreeParams

Update Merkle tree params


```solidity
function setTreeParams(bytes32 treeRoot_, string calldata treeCid_) external onlyRole(SET_TREE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`treeRoot_`|`bytes32`|New root|
|`treeCid_`|`string`|New CID|


### setName

Update the human-readable name


```solidity
function setName(string calldata name) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|New name|


### getInitializedVersion

Initialized version for upgradeable tooling


```solidity
function getInitializedVersion() external view returns (uint64);
```

### initialize

Initialize the gate instance.


```solidity
function initialize(
    uint256 curveId_,
    bytes32 treeRoot_,
    string calldata treeCid_,
    string calldata name_,
    address admin
) public virtual onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId_`|`uint256`||
|`treeRoot_`|`bytes32`||
|`treeCid_`|`string`||
|`name_`|`string`||
|`admin`|`address`|Address to be granted DEFAULT_ADMIN_ROLE.|


### isConsumed

Returns whether a member already consumed eligibility


```solidity
function isConsumed(address member) public view returns (bool);
```

### verifyProof

Verify proof for a member against current tree


```solidity
function verifyProof(address member, bytes32[] calldata proof) public view returns (bool);
```

### hashLeaf

Hash leaf encoding for addresses in the Merkle tree


```solidity
function hashLeaf(address member) public pure returns (bytes32);
```

### _consume


```solidity
function _consume(bytes32[] calldata proof) internal;
```

### _setTreeParams


```solidity
function _setTreeParams(bytes32 treeRoot_, string calldata treeCid_) internal;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

### __checkRole


```solidity
function __checkRole(bytes32 role) internal view override;
```

