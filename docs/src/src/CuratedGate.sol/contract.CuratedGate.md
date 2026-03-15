# CuratedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/CuratedGate.sol)

**Inherits:**
[ICuratedGate](/src/interfaces/ICuratedGate.sol/interface.ICuratedGate.md), [MerkleGate](/src/abstract/MerkleGate.sol/abstract.MerkleGate.md)

Merkle gate for Curated Module


## State Variables
### MODULE

```solidity
ICuratedModule public immutable MODULE
```


### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### DEFAULT_BOND_CURVE_ID
Cached default bond curve id from Accounting.


```solidity
uint256 public immutable DEFAULT_BOND_CURVE_ID
```


### META_REGISTRY

```solidity
IMetaRegistry public immutable META_REGISTRY
```


## Functions
### constructor


```solidity
constructor(address module) ;
```

### initialize


```solidity
function initialize(uint256 curveId, bytes32 treeRoot, string calldata treeCid, address admin)
    public
    override(IMerkleGate, MerkleGate)
    initializer;
```

### createNodeOperator

Create an empty Node Operator for the caller if eligible.
Stores provided name/description in MetaRegistry. Marks caller as consumed.


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


