# IGateSeal
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IGateSeal.sol)


## Functions
### get_sealing_committee


```solidity
function get_sealing_committee() external view returns (address);
```

### get_seal_duration_seconds


```solidity
function get_seal_duration_seconds() external view returns (uint256);
```

### get_sealables


```solidity
function get_sealables() external view returns (address[] memory);
```

### get_expiry_timestamp


```solidity
function get_expiry_timestamp() external view returns (uint256);
```

### is_expired


```solidity
function is_expired() external view returns (bool);
```

### seal


```solidity
function seal(address[] memory _sealables) external;
```

