# IStakingModuleV2
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IStakingModule.sol)


## Functions
### getTotalModuleStake

Returns the total tracked stake of the module in wei.

This is the sum of the activation base for active validators and tracked extra stake.
The tracked extra is intentionally reduced on withdrawal reporting rather than on intermediate validator balance decreases.


```solidity
function getTotalModuleStake() external view returns (uint256 totalModuleStakeWei);
```

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


