# VettedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/VettedGate.sol)

**Inherits:**
[IVettedGate](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IVettedGate.sol/interface.IVettedGate.md), AccessControlEnumerableUpgradeable, [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)


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


### START_REFERRAL_SEASON_ROLE

```solidity
bytes32 public constant START_REFERRAL_SEASON_ROLE = keccak256("START_REFERRAL_SEASON_ROLE")
```


### END_REFERRAL_SEASON_ROLE

```solidity
bytes32 public constant END_REFERRAL_SEASON_ROLE = keccak256("END_REFERRAL_SEASON_ROLE")
```


### MODULE
Address of the Staking Module


```solidity
ICSModule public immutable MODULE
```


### ACCOUNTING
Address of the CS Accounting


```solidity
IAccounting public immutable ACCOUNTING
```


### curveId
Id of the bond curve to be assigned for the eligible members


```solidity
uint256 public curveId
```


### treeRoot
Root of the eligible members Merkle Tree


```solidity
bytes32 public treeRoot
```


### treeCid
CID of the eligible members Merkle Tree


```solidity
string public treeCid
```


### _consumedAddresses

```solidity
mapping(address => bool) internal _consumedAddresses
```


### isReferralProgramSeasonActive
Optional referral program ///


```solidity
bool public isReferralProgramSeasonActive
```


### referralProgramSeasonNumber

```solidity
uint256 public referralProgramSeasonNumber
```


### referralCurveId
Id of the bond curve for referral program


```solidity
uint256 public referralCurveId
```


### referralsThreshold
Number of referrals required for bond curve claim


```solidity
uint256 public referralsThreshold
```


### _referralCounts
Referral counts for referrers for seasons


```solidity
mapping(bytes32 => uint256) internal _referralCounts
```


### _consumedReferrers

```solidity
mapping(bytes32 => bool) internal _consumedReferrers
```


## Functions
### constructor


```solidity
constructor(address module) ;
```

### initialize


```solidity
function initialize(uint256 _curveId, bytes32 _treeRoot, string calldata _treeCid, address admin)
    external
    initializer;
```

### resume

Resume the contract


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause the contract for a given duration
Pausing the contract prevent creating new node operators using VettedGate
and claiming beneficial curve for the existing ones


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause|


### startNewReferralProgramSeason

Start referral program season


```solidity
function startNewReferralProgramSeason(uint256 _referralCurveId, uint256 _referralsThreshold)
    external
    onlyRole(START_REFERRAL_SEASON_ROLE)
    returns (uint256 season);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_referralCurveId`|`uint256`|Curve Id for the referral curve|
|`_referralsThreshold`|`uint256`|Minimum number of referrals to be eligible to claim the curve|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`season`|`uint256`|Id of the started season|


### endCurrentReferralProgramSeason

End referral program season


```solidity
function endCurrentReferralProgramSeason() external onlyRole(END_REFERRAL_SEASON_ROLE);
```

### addNodeOperatorETH

Add a new Node Operator using ETH as a bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators or claim the beneficial curve
via a particular instance of VettedGate.


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
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional. Management properties to be used for the Node Operator. managerAddress: Used as `managerAddress` for the Node Operator. If not passed `msg.sender` will be used. rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `msg.sender` will be used. extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`. If set to true `resetNodeOperatorManagerAddress` method will be disabled|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|
|`referrer`|`address`|Optional. Referrer address. Should be passed when Node Operator is created using partners integration|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator|


### addNodeOperatorStETH

Add a new Node Operator using stETH as a bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create more Node Operators or claim the beneficial curve
via a particular instance of VettedGate.


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
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional. Management properties to be used for the Node Operator. managerAddress: Used as `managerAddress` for the Node Operator. If not passed `msg.sender` will be used. rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `msg.sender` will be used. extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`. If set to true `resetNodeOperatorManagerAddress` method will be disabled|
|`permit`|`IAccounting.PermitInput`|Optional. Permit to use stETH as bond|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|
|`referrer`|`address`|Optional. Referrer address. Should be passed when Node Operator is created using partners integration|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator|


### addNodeOperatorWstETH

Add a new Node Operator using wstETH as a bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create more Node Operators or claim the beneficial curve
via a particular instance of VettedGate.


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
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional. Management properties to be used for the Node Operator. managerAddress: Used as `managerAddress` for the Node Operator. If not passed `msg.sender` will be used. rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `msg.sender` will be used. extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`. If set to true `resetNodeOperatorManagerAddress` method will be disabled|
|`permit`|`IAccounting.PermitInput`|Optional. Permit to use wstETH as bond|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|
|`referrer`|`address`|Optional. Referrer address. Should be passed when Node Operator is created using partners integration|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the created Node Operator|


### claimBondCurve

Claim the bond curve for the eligible Node Operator.
msg.sender is marked as consumed and will not be able to create Node Operators or claim the beneficial curve
via a particular instance of VettedGate.

Should be called by the reward address of the Node Operator
In case of the extended manager permissions, should be called by the manager address


```solidity
function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|


### claimReferrerBondCurve

Claim the referral program bond curve for the eligible Node Operator


```solidity
function claimReferrerBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|


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


### getReferralsCount

Get the number of referrals for the given referrer in the current or last season


```solidity
function getReferralsCount(address referrer) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`referrer`|`address`|Referrer address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of referrals for the given referrer in the current or last season|


### getReferralsCount

Get the number of referrals for the given referrer in the current or last season


```solidity
function getReferralsCount(address referrer, uint256 season) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`referrer`|`address`|Referrer address|
|`season`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of referrals for the given referrer in the current or last season|


### getInitializedVersion

Initialized version for upgradeable tooling


```solidity
function getInitializedVersion() external view returns (uint64);
```

### isReferrerConsumed

Check if the address has already consumed referral program bond curve


```solidity
function isReferrerConsumed(address referrer) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`referrer`|`address`|Address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Consumed flag|


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

### _bumpReferralCount


```solidity
function _bumpReferralCount(address referrer, uint256 referralNodeOperatorId) internal;
```

### _seasonedAddress


```solidity
function _seasonedAddress(address referrer) internal view returns (bytes32);
```

### _onlyNodeOperatorOwner

Verifies that the sender is the owner of the node operator


```solidity
function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

### _seasonedAddress


```solidity
function _seasonedAddress(address referrer, uint256 season) internal pure returns (bytes32);
```

