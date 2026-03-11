# PausableWithRoles
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/abstract/PausableWithRoles.sol)

**Inherits:**
[IPausableWithRoles](/src/interfaces/IPausableWithRoles.sol/interface.IPausableWithRoles.md), [PausableUntil](/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md)

**Title:**
PausableWithRoles

Functions can be paused and resumed only by the authorized roles

Abstract contract providing mechanisms for pausing and resuming contract functions based on roles.


## State Variables
### PAUSE_ROLE

```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE

```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


## Functions
### resume

Resumes the contract functions that were previously paused.

Can only be called by an account with the RESUME_ROLE.


```solidity
function resume() external;
```

### pauseFor

Pauses the contract functions for a specified duration.

Can only be called by an account with the PAUSE_ROLE.


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|The duration (in seconds) for which the contract functions should be paused.|


### __checkRole

Internal function to check if the caller has the required role.


```solidity
function __checkRole(bytes32 role) internal view virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`role`|`bytes32`|The role to check against the caller's permissions.|


