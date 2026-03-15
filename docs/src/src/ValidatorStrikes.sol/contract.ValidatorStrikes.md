# ValidatorStrikes
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/ValidatorStrikes.sol)

**Inherits:**
[IValidatorStrikes](/src/interfaces/IValidatorStrikes.sol/interface.IValidatorStrikes.md), Initializable, AccessControlEnumerableUpgradeable

**Author:**
vgorkavenko


## State Variables
### ORACLE

```solidity
address public immutable ORACLE
```


### MODULE

```solidity
IBaseModule public immutable MODULE
```


### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### EXIT_PENALTIES

```solidity
IExitPenalties public immutable EXIT_PENALTIES
```


### PARAMETERS_REGISTRY

```solidity
IParametersRegistry public immutable PARAMETERS_REGISTRY
```


### ejector

```solidity
IEjector public ejector
```


### treeRoot
The latest Merkle Tree root


```solidity
bytes32 public treeRoot
```


### treeCid
CID of the last published Merkle tree


```solidity
string public treeCid
```


## Functions
### onlyOracle


```solidity
modifier onlyOracle() ;
```

### constructor


```solidity
constructor(address module, address oracle) ;
```

### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(address admin, address _ejector) external initializer;
```

### setEjector

Set the address of the Ejector contract


```solidity
function setEjector(address _ejector) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_ejector`|`address`|Address of the Ejector contract|


### processOracleReport

Receive the data of the Merkle tree from the Oracle contract and process it

New tree might be empty and it is valid value because of `strikesLifetime`


```solidity
function processOracleReport(bytes32 _treeRoot, string calldata _treeCid) external onlyOracle;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treeRoot`|`bytes32`|Root of the Merkle tree|
|`_treeCid`|`string`|an IPFS CID of the tree|


### processBadPerformanceProof

Report multiple keys as bad performing


```solidity
function processBadPerformanceProof(
    KeyStrikes[] calldata keyStrikesList,
    bytes32[] calldata proof,
    bool[] calldata proofFlags,
    address refundRecipient
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikesList`|`KeyStrikes[]`|List of KeyStrikes structs|
|`proof`|`bytes32[]`|Multi-proof of the strikes|
|`proofFlags`|`bool[]`|Flags to process the multi-proof, see OZ `processMultiProof`|
|`refundRecipient`|`address`|Address to send the refund to|


### getInitializedVersion

Returns the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

### verifyProof

Check the contract accepts the provided multi-proof


```solidity
function verifyProof(
    KeyStrikes[] calldata keyStrikesList,
    bytes[] memory pubkeys,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikesList`|`KeyStrikes[]`|List of KeyStrikes structs|
|`pubkeys`|`bytes[]`|Public keys corresponding to each entry in keyStrikesList|
|`proof`|`bytes32[]`|Multi-proof of the strikes|
|`proofFlags`|`bool[]`|Flags to process the multi-proof, see OZ `processMultiProof`|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if proof is accepted|


### hashLeaf

Get a hash of a leaf in a tree of strikes

Double hash the leaf to prevent second pre-image attacks


```solidity
function hashLeaf(KeyStrikes calldata keyStrikes, bytes memory pubkey) public pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikes`|`KeyStrikes`|KeyStrikes struct|
|`pubkey`|`bytes`|Public key|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash of the leaf|


### _setEjector


```solidity
function _setEjector(address _ejector) internal;
```

### _ejectByStrikes


```solidity
function _ejectByStrikes(
    KeyStrikes calldata keyStrikes,
    bytes memory pubkey,
    uint256 value,
    address refundRecipient
) internal;
```

### _onlyOracle


```solidity
function _onlyOracle() internal view;
```

