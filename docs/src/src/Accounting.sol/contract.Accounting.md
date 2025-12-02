# Accounting
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/Accounting.sol)

**Inherits:**
[IAccounting](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IAccounting.sol/interface.IAccounting.md), [BondCore](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/BondCore.sol/abstract.BondCore.md), [BondCurve](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/BondCurve.sol/abstract.BondCurve.md), [BondLock](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/BondLock.sol/abstract.BondLock.md), [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), AccessControlEnumerableUpgradeable, [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)

**Author:**
vgorkavenko

This contract stores the Node Operators' bonds in the form of stETH shares,
so it should be considered in the recovery process


## State Variables
### PAUSE_ROLE

```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE

```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


### MANAGE_BOND_CURVES_ROLE

```solidity
bytes32 public constant MANAGE_BOND_CURVES_ROLE = keccak256("MANAGE_BOND_CURVES_ROLE")
```


### SET_BOND_CURVE_ROLE

```solidity
bytes32 public constant SET_BOND_CURVE_ROLE = keccak256("SET_BOND_CURVE_ROLE")
```


### RECOVERER_ROLE

```solidity
bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE")
```


### MODULE

```solidity
ICSModule public immutable MODULE
```


### FEE_DISTRIBUTOR

```solidity
IFeeDistributor public immutable FEE_DISTRIBUTOR
```


### _feeDistributorOld
DEPRECATED

**Note:**
oz-renamed-from: feeDistributor


```solidity
IFeeDistributor internal _feeDistributorOld
```


### chargePenaltyRecipient

```solidity
address public chargePenaltyRecipient
```


### _feeSplits

```solidity
mapping(uint256 nodeOperatorId => FeeSplit[]) internal _feeSplits
```


### _pendingSharesToSplit

```solidity
mapping(uint256 nodeOperatorId => uint256 pendingSharesToSplit) internal _pendingSharesToSplit
```


### _rewardsClaimers

```solidity
mapping(uint256 nodeOperatorId => address rewardsClaimer) internal _rewardsClaimers
```


## Functions
### onlyModule


```solidity
modifier onlyModule() ;
```

### constructor


```solidity
constructor(
    address lidoLocator,
    address module,
    address feeDistributor,
    uint256 minBondLockPeriod,
    uint256 maxBondLockPeriod
) BondCore(lidoLocator) BondLock(minBondLockPeriod, maxBondLockPeriod);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lidoLocator`|`address`|Lido locator contract address|
|`module`|`address`|Community Staking Module contract address|
|`feeDistributor`|`address`|Fee Distributor contract address|
|`minBondLockPeriod`|`uint256`|Min time in seconds for the bondLock period|
|`maxBondLockPeriod`|`uint256`|Max time in seconds for the bondLock period|


### initialize


```solidity
function initialize(
    BondCurveIntervalInput[] calldata bondCurve,
    address admin,
    uint256 bondLockPeriod,
    address _chargePenaltyRecipient
) external reinitializer(3);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bondCurve`|`BondCurveIntervalInput[]`|Initial bond curve|
|`admin`|`address`|Admin role member address|
|`bondLockPeriod`|`uint256`|Bond lock period in seconds|
|`_chargePenaltyRecipient`|`address`|Recipient of the charge penalty type|


### finalizeUpgradeV3

This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.


```solidity
function finalizeUpgradeV3() external reinitializer(3);
```

### resume

Resume reward claims and deposits


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause reward claims and deposits for `duration` seconds

Must be called together with `CSModule.pauseFor`


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### setChargePenaltyRecipient

Set charge recipient address


```solidity
function setChargePenaltyRecipient(address _chargePenaltyRecipient) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_chargePenaltyRecipient`|`address`|Charge recipient address|


### setBondLockPeriod

Set bond lock period


```solidity
function setBondLockPeriod(uint256 period) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`period`|`uint256`|Period in seconds to retain bond lock|


### setFeeSplits

Set fee splits for the given Node Operator


```solidity
function setFeeSplits(
    uint256 nodeOperatorId,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof,
    FeeSplit[] calldata feeSplits
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|
|`feeSplits`|`FeeSplit[]`|Array of FeeSplit structs defining recipients and their shares in basis points Total shares must be <= 10_000 (100%). Remainder goes to the Node Operator's bond|


### addBondCurve

Add a new bond curve


```solidity
function addBondCurve(BondCurveIntervalInput[] calldata bondCurve)
    external
    onlyRole(MANAGE_BOND_CURVES_ROLE)
    returns (uint256 id);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bondCurve`|`BondCurveIntervalInput[]`|Bond curve definition to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`id`|`uint256`|Id of the added curve|


### updateBondCurve

Update existing bond curve

If the curve is updated to a curve with higher values for any point,
Extensive checks and actions should be performed by the method caller to avoid
inconsistency in the keys accounting. A manual update of the depositable validators count
in CSM might be required to ensure that the keys pointers are consistent.


```solidity
function updateBondCurve(uint256 curveId, BondCurveIntervalInput[] calldata bondCurve)
    external
    onlyRole(MANAGE_BOND_CURVES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve ID to update|
|`bondCurve`|`BondCurveIntervalInput[]`|Bond curve definition|


### setBondCurve

Set the bond curve for the given Node Operator

Updates depositable validators count in CSM to ensure key pointers consistency


```solidity
function setBondCurve(uint256 nodeOperatorId, uint256 curveId) external onlyRole(SET_BOND_CURVE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`curveId`|`uint256`|ID of the bond curve to set|


### depositETH

Stake user's ETH with Lido and deposit stETH to the bond

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositETH(address from, uint256 nodeOperatorId) external payable whenResumed onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address to stake ETH and deposit stETH from|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### depositETH

Stake user's ETH with Lido and deposit stETH to the bond

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositETH(uint256 nodeOperatorId) external payable whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### depositStETH

Deposit user's stETH to the bond for the given Node Operator

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositStETH(address from, uint256 nodeOperatorId, uint256 stETHAmount, PermitInput calldata permit)
    external
    whenResumed
    onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address to deposit stETH from.|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`stETHAmount`|`uint256`|Amount of stETH to deposit|
|`permit`|`PermitInput`|stETH permit for the contract|


### depositStETH

Deposit user's stETH to the bond for the given Node Operator

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositStETH(uint256 nodeOperatorId, uint256 stETHAmount, PermitInput calldata permit)
    external
    whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`stETHAmount`|`uint256`|Amount of stETH to deposit|
|`permit`|`PermitInput`|stETH permit for the contract|


### depositWstETH

Unwrap the user's wstETH and deposit stETH to the bond for the given Node Operator

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositWstETH(address from, uint256 nodeOperatorId, uint256 wstETHAmount, PermitInput calldata permit)
    external
    whenResumed
    onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Address to unwrap wstETH from|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`wstETHAmount`|`uint256`|Amount of wstETH to deposit|
|`permit`|`PermitInput`|wstETH permit for the contract|


### depositWstETH

Unwrap the user's wstETH and deposit stETH to the bond for the given Node Operator

Called by CSM exclusively. CSM should check node operator existence and update depositable validators count


```solidity
function depositWstETH(uint256 nodeOperatorId, uint256 wstETHAmount, PermitInput calldata permit)
    external
    whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`wstETHAmount`|`uint256`|Amount of wstETH to deposit|
|`permit`|`PermitInput`|wstETH permit for the contract|


### claimRewardsStETH

Claim full reward (fee + bond) in stETH for the given Node Operator with desirable value.
`rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond

It's impossible to use single-leaf proof via this method, so this case should be treated carefully by
off-chain tooling, e.g. to make sure a tree has at least 2 leafs.


```solidity
function claimRewardsStETH(
    uint256 nodeOperatorId,
    uint256 stETHAmount,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external whenResumed returns (uint256 claimedShares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`stETHAmount`|`uint256`|Amount of stETH to claim|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimedShares`|`uint256`|shares Amount of stETH shares claimed|


### claimRewardsWstETH

Claim full reward (fee + bond) in wstETH for the given Node Operator available for this moment.
`rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond

It's impossible to use single-leaf proof via this method, so this case should be treated carefully by
off-chain tooling, e.g. to make sure a tree has at least 2 leafs.


```solidity
function claimRewardsWstETH(
    uint256 nodeOperatorId,
    uint256 wstETHAmount,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external whenResumed returns (uint256 claimedWstETH);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`wstETHAmount`|`uint256`|Amount of wstETH to claim|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimedWstETH`|`uint256`|claimedWstETHAmount Amount of wstETH claimed|


### claimRewardsUnstETH

Request full reward (fee + bond) in Withdrawal NFT (unstETH) for the given Node Operator available for this moment.
`rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond

Reverts if amount isn't between `MIN_STETH_WITHDRAWAL_AMOUNT` and `MAX_STETH_WITHDRAWAL_AMOUNT`


```solidity
function claimRewardsUnstETH(
    uint256 nodeOperatorId,
    uint256 stETHAmount,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external whenResumed returns (uint256 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`stETHAmount`|`uint256`|Amount of ETH to request|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|Withdrawal NFT ID|


### lockBondETH

Lock bond in ETH for the given Node Operator

Called by CSM exclusively


```solidity
function lockBondETH(uint256 nodeOperatorId, uint256 amount) external onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to lock in ETH (stETH)|


### releaseLockedBondETH

Release locked bond in ETH for the given Node Operator

Called by CSM exclusively


```solidity
function releaseLockedBondETH(uint256 nodeOperatorId, uint256 amount) external onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to release in ETH (stETH)|


### compensateLockedBondETH

Compensate locked bond ETH for the given Node Operator

Called by CSM exclusively


```solidity
function compensateLockedBondETH(uint256 nodeOperatorId) external payable onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### settleLockedBondETH

Settle locked bond ETH for the given Node Operator

Called by CSM exclusively


```solidity
function settleLockedBondETH(uint256 nodeOperatorId) external onlyModule returns (bool applied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### penalize

Penalize bond by burning stETH shares of the given Node Operator

Penalty application has a priority over the locked bond.
Method call can result in the remaining bond being lower than the locked bond.


```solidity
function penalize(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool fullyBurned);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to penalize in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fullyBurned`|`bool`|True if the bond was fully burned, false otherwise|


### chargeFee

Charge fee from bond by transferring stETH shares of the given Node Operator to the charge recipient

Charge confiscation has a priority over the locked bond.
Method call can result in the remaining bond being lower than the locked bond.


```solidity
function chargeFee(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool fullyCharged);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to charge in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fullyCharged`|`bool`|True if the bond was fully charged, false otherwise|


### pullAndSplitFeeRewards

Pull fees (if proof provided) from FeeDistributor to the Node Operator's bond and split pending according to configured fee splits.

Permissionless method. Can be called before penalty application to ensure that rewards are also penalized and split.


```solidity
function pullAndSplitFeeRewards(
    uint256 nodeOperatorId,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|


### setCustomRewardsClaimer

Set custom rewards claimer for the given Node Operator. This address will be able to claim rewards on behalf of the Node Operator.
The rewards will be transferred to the Node Operator's reward address as usual.


```solidity
function setCustomRewardsClaimer(uint256 nodeOperatorId, address rewardsClaimer) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`rewardsClaimer`|`address`|Address allowed to claim rewards on behalf of the Node Operator|


### recoverERC20

Allows sender to recover ERC20 tokens held by the contract


```solidity
function recoverERC20(address token, uint256 amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to recover|
|`amount`|`uint256`|The amount of the ERC20 token to recover Emits an ERC20Recovered event upon success Optionally, the inheriting contract can override this function to add additional restrictions|


### recoverStETHShares

Recover all stETH shares from the contract

Accounts for the bond funds stored during recovery


```solidity
function recoverStETHShares() external;
```

### renewBurnerAllowance

Service method to update allowance to Burner in case it has changed


```solidity
function renewBurnerAllowance() external;
```

### getInitializedVersion

Get the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

### getFeeSplits

Set fee splits for the given Node Operator


```solidity
function getFeeSplits(uint256 nodeOperatorId) external view returns (FeeSplit[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`FeeSplit[]`|Array of FeeSplit structs defining recipients and their shares in basis points|


### getCustomRewardsClaimer

Get the custom rewards claimer for the given Node Operator. This address is allowed to claim rewards on behalf of the Node Operator.
The rewards are still transferred to the Node Operator's reward address as usual.


```solidity
function getCustomRewardsClaimer(uint256 nodeOperatorId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|rewardsClaimer Address allowed to claim rewards on behalf of the Node Operator|


### getPendingSharesToSplit

Get the number of the pending shares to be split for the given Node Operator


```solidity
function getPendingSharesToSplit(uint256 nodeOperatorId) external view returns (uint256);
```

### getUnbondedKeysCount

Get the number of the unbonded keys


```solidity
function getUnbondedKeysCount(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Unbonded keys count|


### getUnbondedKeysCountToEject

Get the number of the unbonded keys to be ejected using a forcedTargetLimit
Locked bond is not considered for this calculation to allow Node Operators to
compensate the locked bond via `compensateLockedBondETH` method before the ejection happens


```solidity
function getUnbondedKeysCountToEject(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Unbonded keys count|


### getBondAmountByKeysCountWstETH

Get the bond amount in wstETH required for the `keysCount` keys using the default bond curve


```solidity
function getBondAmountByKeysCountWstETH(uint256 keysCount, uint256 curveId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keysCount`|`uint256`|Keys count to calculate the required bond amount|
|`curveId`|`uint256`|Id of the curve to perform calculations against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|wstETH amount required for the `keysCount`|


### getRequiredBondForNextKeysWstETH

Get the required bond in wstETH (inc. missed and excess) for the given Node Operator to upload new keys


```solidity
function getRequiredBondForNextKeysWstETH(uint256 nodeOperatorId, uint256 additionalKeys)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`additionalKeys`|`uint256`|Number of new keys to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Required bond in wstETH|


### getClaimableBondShares

Get current claimable bond in stETH shares for the given Node Operator


```solidity
function getClaimableBondShares(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Current claimable bond in stETH shares|


### getClaimableRewardsAndBondShares

Get current claimable bond in stETH shares for the given Node Operator
Includes potential rewards distributed by the Fee Distributor


```solidity
function getClaimableRewardsAndBondShares(
    uint256 nodeOperatorId,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external view returns (uint256 claimableShares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableShares`|`uint256`|Current claimable bond in stETH shares|


### getBondSummary

Get current and required bond amounts in ETH (stETH) for the given Node Operator

To calculate excess bond amount subtract `required` from `current` value.
To calculate missed bond amount subtract `current` from `required` value


```solidity
function getBondSummary(uint256 nodeOperatorId) public view returns (uint256 current, uint256 required);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`current`|`uint256`|Current bond amount in ETH|
|`required`|`uint256`|Required bond amount in ETH|


### getBondSummaryShares

Get current and required bond amounts in stETH shares for the given Node Operator

To calculate excess bond amount subtract `required` from `current` value.
To calculate missed bond amount subtract `current` from `required` value


```solidity
function getBondSummaryShares(uint256 nodeOperatorId) public view returns (uint256 current, uint256 required);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`current`|`uint256`|Current bond amount in stETH shares|
|`required`|`uint256`|Required bond amount in stETH shares|


### getRequiredBondForNextKeys

Get the required bond in ETH (inc. missed and excess) for the given Node Operator to upload new deposit data


```solidity
function getRequiredBondForNextKeys(uint256 nodeOperatorId, uint256 additionalKeys) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`additionalKeys`|`uint256`|Number of new keys to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Required bond amount in ETH|


### _pullAndSplitFeeRewards


```solidity
function _pullAndSplitFeeRewards(
    uint256 nodeOperatorId,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) internal returns (uint256 claimableShares);
```

### _unwrapPermitIfRequired


```solidity
function _unwrapPermitIfRequired(address token, address from, PermitInput calldata permit) internal;
```

### _getClaimableBondShares

Calculates claimable bond shares accounting for locked bond and withdrawn validators


```solidity
function _getClaimableBondShares(uint256 nodeOperatorId) internal view returns (uint256);
```

### _getRequiredBond


```solidity
function _getRequiredBond(uint256 nodeOperatorId, uint256 additionalKeys) internal view returns (uint256);
```

### _getRequiredBondShares


```solidity
function _getRequiredBondShares(uint256 nodeOperatorId, uint256 additionalKeys) internal view returns (uint256);
```

### _getUnbondedKeysCount

Unbonded stands for the amount of keys not fully covered with bond


```solidity
function _getUnbondedKeysCount(uint256 nodeOperatorId, bool includeLockedBond) internal view returns (uint256);
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

### _onlyExistingNodeOperator


```solidity
function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view;
```

### _onlyNodeOperatorOwner


```solidity
function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view;
```

### _onlyModule


```solidity
function _onlyModule() internal view;
```

### _checkAndGetEligibleNodeOperatorProperties


```solidity
function _checkAndGetEligibleNodeOperatorProperties(uint256 nodeOperatorId)
    internal
    view
    returns (NodeOperatorManagementProperties memory no);
```

### _setChargePenaltyRecipient


```solidity
function _setChargePenaltyRecipient(address _chargePenaltyRecipient) private;
```

