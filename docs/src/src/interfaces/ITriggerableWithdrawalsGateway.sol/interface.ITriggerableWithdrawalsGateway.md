# ITriggerableWithdrawalsGateway
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/ITriggerableWithdrawalsGateway.sol)


## Functions
### ADD_FULL_WITHDRAWAL_REQUEST_ROLE


```solidity
function ADD_FULL_WITHDRAWAL_REQUEST_ROLE() external view returns (bytes32);
```

### DEFAULT_ADMIN_ROLE


```solidity
function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
```

### getRoleMember


```solidity
function getRoleMember(bytes32 role, uint256 index) external view returns (address);
```

### grantRole


```solidity
function grantRole(bytes32 role, address account) external;
```

### revokeRole


```solidity
function revokeRole(bytes32 role, address account) external;
```

### hasRole


```solidity
function hasRole(bytes32 role, address account) external view returns (bool);
```

### triggerFullWithdrawals

Reverts if:
- The caller does not have the `ADD_FULL_WITHDRAWAL_REQUEST_ROLE`
- The total fee value sent is insufficient to cover all provided TW requests.
- There is not enough limit quota left in the current frame to process all requests.

Submits Triggerable Withdrawal Requests to the Withdrawal Vault as full withdrawal requests
for the specified validator public keys.


```solidity
function triggerFullWithdrawals(
    ValidatorData[] calldata triggerableExitsData,
    address refundRecipient,
    uint256 exitType
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`triggerableExitsData`|`ValidatorData[]`|An array of `ValidatorData` structs, each representing a validator for which a withdrawal request will be submitted. Each entry includes: - `stakingModuleId`: ID of the staking module. - `nodeOperatorId`: ID of the node operator. - `pubkey`: Validator public key, 48 bytes length.|
|`refundRecipient`|`address`|The address that will receive any excess ETH sent for fees.|
|`exitType`|`uint256`|A parameter indicating the type of exit, passed to the Staking Module. Emits `TriggerableExitRequest` event for each validator in list.|


