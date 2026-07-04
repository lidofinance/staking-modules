# IBurner
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IBurner.sol)


## Functions
### REQUEST_BURN_SHARES_ROLE


```solidity
function REQUEST_BURN_SHARES_ROLE() external view returns (bytes32);
```

### REQUEST_BURN_MY_STETH_ROLE


```solidity
function REQUEST_BURN_MY_STETH_ROLE() external view returns (bytes32);
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

### requestBurnMyShares


```solidity
function requestBurnMyShares(uint256 _sharesAmountToBurn) external;
```

