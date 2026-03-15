# Accounting
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/Accounting.sol)

**Inherits:**
[IAccounting](/src/interfaces/IAccounting.sol/interface.IAccounting.md), [BondCore](/src/abstract/BondCore.sol/abstract.BondCore.md), [BondCurve](/src/abstract/BondCurve.sol/abstract.BondCurve.md), [BondLock](/src/abstract/BondLock.sol/abstract.BondLock.md), [FeeSplits](/src/abstract/FeeSplits.sol/abstract.FeeSplits.md), [PausableWithRoles](/src/abstract/PausableWithRoles.sol/abstract.PausableWithRoles.md), AccessControlEnumerableUpgradeable, [AssetRecoverer](/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)

**Author:**
vgorkavenko

This contract stores the Node Operators' bonds in the form of stETH shares,
so it should be considered in the recovery process


## State Variables
### INITIALIZED_VERSION

```solidity
uint64 internal constant INITIALIZED_VERSION = 3
```


### MANAGE_BOND_CURVES_ROLE

```solidity
bytes32 public constant MANAGE_BOND_CURVES_ROLE = keccak256("MANAGE_BOND_CURVES_ROLE")
```


### SET_BOND_CURVE_ROLE

```solidity
bytes32 public constant SET_BOND_CURVE_ROLE = keccak256("SET_BOND_CURVE_ROLE")
```


### MODULE

```solidity
IBaseModule public immutable MODULE
```


### FEE_DISTRIBUTOR

```solidity
IFeeDistributor public immutable FEE_DISTRIBUTOR
```


### _rewardsClaimers

```solidity
mapping(uint256 nodeOperatorId => address rewardsClaimer) internal _rewardsClaimers
```


### chargePenaltyRecipient

```solidity
address public chargePenaltyRecipient
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
|`lidoLocator`|`address`|Lido Locator contract address|
|`module`|`address`|Staking Module contract address|
|`feeDistributor`|`address`|Fee Distributor contract address|
|`minBondLockPeriod`|`uint256`|Min time in seconds for the bondLock period|
|`maxBondLockPeriod`|`uint256`|Max time in seconds for the bondLock period|


### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(
    BondCurveIntervalInput[] calldata bondCurve,
    address admin,
    uint256 bondLockPeriod,
    address _chargePenaltyRecipient
) external reinitializer(INITIALIZED_VERSION);
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
To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.


```solidity
function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION);
```

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


### updateFeeSplits

Set fee splits for the given Node Operator

FeeSplits can be updated either when there are no splits currently or when there are splits now,
provided all node operator rewards are distributed and split. It is possible to set splits while
there are undistributed node operator rewards and no splits are currently set.
This will result in all undistributed node operator rewards being split.
If a node operator has never received any node operator rewards, they can set initial splits.
However, further change will be possible only after getting and splitting the first rewards.


```solidity
function updateFeeSplits(
    uint256 nodeOperatorId,
    FeeSplit[] calldata feeSplits,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`feeSplits`|`FeeSplit[]`|Array of FeeSplit structs defining recipients and their shares in basis points Total shares must be <= 10_000 (100%). Remainder goes to the Node Operator's bond|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator. Optional|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards. Optional|


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
in staking module might be required to ensure that the keys pointers are consistent.


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

Updates depositable validators count in staking module to ensure key pointers consistency


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

Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count


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

Permissionless. Enqueues Node Operator's keys if needed


```solidity
function depositETH(uint256 nodeOperatorId) external payable whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### depositStETH

Deposit user's stETH to the bond for the given Node Operator

Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count


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

Permissionless. Enqueues Node Operator's keys if needed


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

Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count


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

Permissionless. Enqueues Node Operator's keys if needed


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
off-chain tooling, e.g. to make sure a tree has at least 2 leaves.


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
off-chain tooling, e.g. to make sure a tree has at least 2 leaves.


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
|`stETHAmount`|`uint256`|Amount of stETH to request|
|`cumulativeFeeShares`|`uint256`|Cumulative fee stETH shares for the Node Operator|
|`rewardsProof`|`bytes32[]`|Merkle proof of the rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|Withdrawal NFT ID|


### lockBond

Lock bond in ETH for the given Node Operator

Called by staking module exclusively


```solidity
function lockBond(uint256 nodeOperatorId, uint256 amount) external onlyModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to lock in ETH (stETH)|


### releaseLockedBond

Release locked bond in ETH for the given Node Operator

Called by staking module exclusively


```solidity
function releaseLockedBond(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool released);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to release in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`released`|`bool`|True if the bond was released, false if the lock was expired and bond was unlocked instead|


### unlockExpiredLock

Unlock expired locked bond for the given Node Operator


```solidity
function unlockExpiredLock(uint256 nodeOperatorId) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### compensateLockedBond

Compensate locked bond ETH for the given Node Operator

Called by staking module exclusively


```solidity
function compensateLockedBond(uint256 nodeOperatorId) external onlyModule returns (uint256 compensatedAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`compensatedAmount`|`uint256`|Amount compensated in ETH (stETH)|


### settleLockedBond

Settle locked bond ETH for the given Node Operator

Called by staking module exclusively


```solidity
function settleLockedBond(uint256 nodeOperatorId, uint256 maxAmount)
    external
    onlyModule
    returns (uint256 amountSettled);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`maxAmount`|`uint256`|Maximum amount to settle in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountSettled`|`uint256`|Amount settled in ETH (stETH)|


### penalize

Penalize bond by burning stETH shares of the given Node Operator

Penalty application has a priority over the locked bond.
Method call can result in the remaining bond being lower than the locked bond.


```solidity
function penalize(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool penaltyCovered);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to penalize in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`penaltyCovered`|`bool`|True if the penalty was fully covered by bond burn, false otherwise|


### chargeFee

Charge fee from bond by transferring stETH shares of the given Node Operator to the charge recipient

Charge confiscation has a priority over the locked bond.
Method call can result in the remaining bond being lower than the locked bond.


```solidity
function chargeFee(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount to charge in ETH (stETH)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether any shares were actually transferred|


### pullAndSplitFeeRewards

Pull fees (if proof provided) from FeeDistributor to the Node Operator's bond and split according to configured fee splits.


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
|`amount`|`uint256`|The amount of the ERC20 token to recover|


### recoverStETHShares

Recover all stETH shares from the contract

Accounts for the bond funds stored during recovery


```solidity
function recoverStETHShares() external;
```

### getInitializedVersion

Get the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

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
compensate the locked bond via `compensateLockedBond` method before the ejection happens


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

Get the bond amount in wstETH required for the `keysCount` keys for the given bond curve


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


### getNodeOperatorBondInfo

Get all bond-related info for the given Node Operator in one call


```solidity
function getNodeOperatorBondInfo(uint256 nodeOperatorId) external view returns (NodeOperatorBondInfo memory info);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`info`|`NodeOperatorBondInfo`|Bond info containing current bond, required bond, locked bond, bond debt, and pending shares to split|


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

Calculates claimable bond shares accounting for locked bond and withdrawn validators.
Does not subtract pending split transfers, so in rare cases (e.g. paused Accounting, locked or debted bond)
may overestimate operator-receivable amount.
Off-chain integrations should account for `getPendingSharesToSplit`.


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

### __checkRole


```solidity
function __checkRole(bytes32 role) internal view override;
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

