# VettedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/VettedGate.sol)

**Inherits:**
[IVettedGate](/src/interfaces/IVettedGate.sol/interface.IVettedGate.md), [MerkleGate](/src/abstract/MerkleGate.sol/abstract.MerkleGate.md)

Merkle gate for vetted/community members.


## State Variables
### MODULE
Address of the Staking Module.


```solidity
IBaseModule public immutable MODULE
```


### ACCOUNTING
Address of the Accounting.


```solidity
IAccounting public immutable ACCOUNTING
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

### addNodeOperatorETH

Add a new Node Operator using ETH as bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators
or claim the beneficial curve via this VettedGate instance.


```solidity
function addNodeOperatorETH(
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures,
    NodeOperatorManagementProperties calldata managementProperties,
    bytes32[] calldata proof,
    address referrer
) external payable whenResumed returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keysCount`|`uint256`|Signing keys count.|
|`publicKeys`|`bytes`|Public keys to submit.|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples.|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional management properties for the Node Operator.|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate.|
|`referrer`|`address`|Optional referrer address to pass through to module.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator.|


### addNodeOperatorStETH

Add a new Node Operator using stETH as bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators
or claim the beneficial curve via this VettedGate instance.


```solidity
function addNodeOperatorStETH(
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures,
    NodeOperatorManagementProperties calldata managementProperties,
    IAccounting.PermitInput calldata permit,
    bytes32[] calldata proof,
    address referrer
) external whenResumed returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keysCount`|`uint256`|Signing keys count.|
|`publicKeys`|`bytes`|Public keys to submit.|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples.|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional management properties for the Node Operator.|
|`permit`|`IAccounting.PermitInput`|Optional permit to use stETH as bond.|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate.|
|`referrer`|`address`|Optional referrer address to pass through to module.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator.|


### addNodeOperatorWstETH

Add a new Node Operator using wstETH as bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators
or claim the beneficial curve via this VettedGate instance.


```solidity
function addNodeOperatorWstETH(
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures,
    NodeOperatorManagementProperties calldata managementProperties,
    IAccounting.PermitInput calldata permit,
    bytes32[] calldata proof,
    address referrer
) external whenResumed returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keysCount`|`uint256`|Signing keys count.|
|`publicKeys`|`bytes`|Public keys to submit.|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples.|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional management properties for the Node Operator.|
|`permit`|`IAccounting.PermitInput`|Optional permit to use wstETH as bond.|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate.|
|`referrer`|`address`|Optional referrer address to pass through to module.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator.|


### claimBondCurve

Claim the bond curve for an eligible Node Operator.
msg.sender is marked as consumed and will not be able to create Node Operators
or claim again via this VettedGate instance.

Should be called by Node Operator owner.


```solidity
function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator.|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate.|


### _onlyNodeOperatorOwner


```solidity
function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view;
```

