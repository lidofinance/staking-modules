# IStakingModuleV2
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IStakingModule.sol)


## Functions
### allocateDeposits

Validates that provided keys belong to the corresponding operators in the module and calculates deposit allocations for top-up

Reverts if any key doesn't belong to the module or data is invalid

Values depositAmount, topUpLimits, allocations are denominated in wei

allocations list can contain zero values

sum of allocations can be less or equal to maxDepositAmount


```solidity
function allocateDeposits(
    uint256 maxDepositAmount,
    bytes[] calldata pubkeys,
    uint256[] calldata keyIndices,
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxDepositAmount`|`uint256`|Total ether amount available for top-up (must be multiple of 1 gwei)|
|`pubkeys`|`bytes[]`|List of validator public keys to top up|
|`keyIndices`|`uint256[]`|Indices of keys within their respective operators|
|`operatorIds`|`uint256[]`|Node operator IDs that own the keys|
|`topUpLimits`|`uint256[]`|Maximum amount that can be deposited per key based on CL data and SR internal logic.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocations`|`uint256[]`|Amount to deposit to each key|


### updateOperatorBalances

Called by StakingRouter to update node operator total balances.

Total balances are denominated in gwei.

Input format matches validator counts updates from StakingRouter:
`operatorIds` packs ids as bytes8 entries and `totalBalancesGwei` packs values as bytes16 entries.


```solidity
function updateOperatorBalances(bytes calldata operatorIds, bytes calldata totalBalancesGwei) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operatorIds`|`bytes`|Bytes packed array of node operator IDs.|
|`totalBalancesGwei`|`bytes`|Bytes packed array of total balances (validators + pending), in gwei.|


