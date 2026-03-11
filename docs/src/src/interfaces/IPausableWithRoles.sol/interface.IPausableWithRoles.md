# IPausableWithRoles
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IPausableWithRoles.sol)


## Functions
### PAUSE_ROLE


```solidity
function PAUSE_ROLE() external view returns (bytes32);
```

### RESUME_ROLE


```solidity
function RESUME_ROLE() external view returns (bytes32);
```

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


