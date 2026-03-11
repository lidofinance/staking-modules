# IVettedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IVettedGate.sol)

**Inherits:**
[IMerkleGate](/src/interfaces/IMerkleGate.sol/interface.IMerkleGate.md)


## Functions
### MODULE


```solidity
function MODULE() external view returns (IBaseModule);
```

### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### addNodeOperatorETH

Add a new Node Operator using ETH as bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators
or claim the beneficial curve via this VettedGate instance.


```solidity
function addNodeOperatorETH(
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures,
    NodeOperatorManagementProperties memory managementProperties,
    bytes32[] memory proof,
    address referrer
) external payable returns (uint256 nodeOperatorId);
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

Due to stETH rounding issue make sure to approve/sign permit with extra 10 wei to avoid revert.


```solidity
function addNodeOperatorStETH(
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures,
    NodeOperatorManagementProperties memory managementProperties,
    IAccounting.PermitInput memory permit,
    bytes32[] memory proof,
    address referrer
) external returns (uint256 nodeOperatorId);
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

Due to stETH rounding issue make sure to approve/sign permit with extra 10 wei to avoid revert.


```solidity
function addNodeOperatorWstETH(
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures,
    NodeOperatorManagementProperties memory managementProperties,
    IAccounting.PermitInput memory permit,
    bytes32[] memory proof,
    address referrer
) external returns (uint256 nodeOperatorId);
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
function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator.|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate.|


## Errors
### InvalidCurveId

```solidity
error InvalidCurveId();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### NotAllowedToClaim

```solidity
error NotAllowedToClaim();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

