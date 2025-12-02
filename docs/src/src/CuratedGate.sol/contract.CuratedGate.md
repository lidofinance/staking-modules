# CuratedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/CuratedGate.sol)

**Inherits:**
[ICuratedGate](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/ICuratedGate.sol/interface.ICuratedGate.md), AccessControlEnumerableUpgradeable, [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)

Merkle gate for Curated Module v2


## State Variables
### PAUSE_ROLE

```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE

```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


### RECOVERER_ROLE

```solidity
bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE")
```


### SET_TREE_ROLE

```solidity
bytes32 public constant SET_TREE_ROLE = keccak256("SET_TREE_ROLE")
```


### MODULE

```solidity
ICuratedModule public immutable MODULE
```


### MODULE_ID

```solidity
uint256 public immutable MODULE_ID
```


### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### OPERATORS_DATA

```solidity
IOperatorsData public immutable OPERATORS_DATA
```


### treeRoot

```solidity
bytes32 public treeRoot
```


### treeCid

```solidity
string public treeCid
```


### curveId

```solidity
uint256 public curveId
```


### _defaultCurveSet

```solidity
bool internal _defaultCurveSet
```


### _consumedAddresses
Tracks whether an address already consumed its eligibility


```solidity
mapping(address => bool) internal _consumedAddresses
```


## Functions
### constructor


```solidity
constructor(address module, uint256 moduleId, address operatorsData) ;
```

### initialize


```solidity
function initialize(uint256 _curveId, bytes32 _treeRoot, string calldata _treeCid, address admin)
    external
    initializer;
```

### resume

Resume the gate


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause the gate for a given duration


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration in seconds|


### createNodeOperator

Create an empty Node Operator for the caller if eligible.
Stores provided name/description in OperatorsData. Marks caller as consumed.


```solidity
function createNodeOperator(
    string calldata name,
    string calldata description,
    address managerAddress,
    address rewardAddress,
    bytes32[] calldata proof
) external whenResumed returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|Display name of the Node Operator|
|`description`|`string`|Description of the Node Operator|
|`managerAddress`|`address`|Address to set as manager; if zero, defaults will be used by the module|
|`rewardAddress`|`address`|Address to set as rewards receiver; if zero, defaults will be used by the module|
|`proof`|`bytes32[]`|Merkle proof for the caller address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Newly created Node Operator id|


### setTreeParams

Update Merkle tree params


```solidity
function setTreeParams(bytes32 _treeRoot, string calldata _treeCid) external onlyRole(SET_TREE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treeRoot`|`bytes32`|New root|
|`_treeCid`|`string`|New CID|


### getInitializedVersion

Initialized version for upgradeable tooling


```solidity
function getInitializedVersion() external view returns (uint64);
```

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
function _setTreeParams(bytes32 _treeRoot, string calldata _treeCid) internal;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

