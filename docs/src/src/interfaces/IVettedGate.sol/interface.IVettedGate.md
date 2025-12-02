# IVettedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IVettedGate.sol)

**Inherits:**
[IMerkleGate](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IMerkleGate.sol/interface.IMerkleGate.md)


## Functions
### PAUSE_ROLE


```solidity
function PAUSE_ROLE() external view returns (bytes32);
```

### RESUME_ROLE


```solidity
function RESUME_ROLE() external view returns (bytes32);
```

### RECOVERER_ROLE


```solidity
function RECOVERER_ROLE() external view returns (bytes32);
```

### START_REFERRAL_SEASON_ROLE


```solidity
function START_REFERRAL_SEASON_ROLE() external view returns (bytes32);
```

### END_REFERRAL_SEASON_ROLE


```solidity
function END_REFERRAL_SEASON_ROLE() external view returns (bytes32);
```

### MODULE


```solidity
function MODULE() external view returns (ICSModule);
```

### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### curveId


```solidity
function curveId() external view returns (uint256);
```

### isReferralProgramSeasonActive


```solidity
function isReferralProgramSeasonActive() external view returns (bool);
```

### referralProgramSeasonNumber


```solidity
function referralProgramSeasonNumber() external view returns (uint256);
```

### referralCurveId


```solidity
function referralCurveId() external view returns (uint256);
```

### referralsThreshold


```solidity
function referralsThreshold() external view returns (uint256);
```

### pauseFor

Pause the contract for a given duration
Pausing the contract prevent creating new node operators using VettedGate
and claiming beneficial curve for the existing ones


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause|


### resume

Resume the contract


```solidity
function resume() external;
```

### startNewReferralProgramSeason

Start referral program season


```solidity
function startNewReferralProgramSeason(uint256 _referralCurveId, uint256 _referralsThreshold)
    external
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
function endCurrentReferralProgramSeason() external;
```

### addNodeOperatorETH

Add a new Node Operator using ETH as a bond.
At least one deposit data and corresponding bond should be provided.
msg.sender is marked as consumed and will not be able to create Node Operators or claim the beneficial curve
via a particular instance of VettedGate.


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

Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert


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

Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert


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
function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|


### claimReferrerBondCurve

Claim the referral program bond curve for the eligible Node Operator


```solidity
function claimReferrerBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the Node Operator|
|`proof`|`bytes32[]`|Merkle proof of the sender being eligible to join via the gate|


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

Get the number of referrals for the given referrer in the given season


```solidity
function getReferralsCount(address referrer, uint256 season) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`referrer`|`address`|Referrer address|
|`season`|`uint256`|Season number|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of referrals for the given referrer in the given season|


## Events
### ReferrerConsumed

```solidity
event ReferrerConsumed(address indexed referrer, uint256 indexed season);
```

### ReferralProgramSeasonStarted

```solidity
event ReferralProgramSeasonStarted(uint256 indexed season, uint256 referralCurveId, uint256 referralsThreshold);
```

### ReferralProgramSeasonEnded

```solidity
event ReferralProgramSeasonEnded(uint256 indexed season);
```

### ReferralRecorded

```solidity
event ReferralRecorded(address indexed referrer, uint256 indexed season, uint256 indexed referralNodeOperatorId);
```

## Errors
### InvalidCurveId

```solidity
error InvalidCurveId();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### NotAllowedToClaim

```solidity
error NotAllowedToClaim();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

### NotEnoughReferrals

```solidity
error NotEnoughReferrals();
```

### ReferralProgramIsNotActive

```solidity
error ReferralProgramIsNotActive();
```

### ReferralProgramIsActive

```solidity
error ReferralProgramIsActive();
```

### InvalidReferralsThreshold

```solidity
error InvalidReferralsThreshold();
```

