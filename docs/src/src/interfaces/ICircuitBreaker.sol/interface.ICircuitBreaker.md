# ICircuitBreaker
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/interfaces/ICircuitBreaker.sol)


## Functions
### registerPauser


```solidity
function registerPauser(address _pausable, address _newPauser) external;
```

### pause


```solidity
function pause(address _pausable) external;
```

### heartbeat


```solidity
function heartbeat() external;
```

### getPauser


```solidity
function getPauser(address _pausable) external view returns (address);
```

### getPausables


```solidity
function getPausables() external view returns (address[] memory);
```

### getPausableCount


```solidity
function getPausableCount(address _pauser) external view returns (uint256);
```

### isPauserLive


```solidity
function isPauserLive(address _pauser) external view returns (bool);
```

### pauseDuration


```solidity
function pauseDuration() external view returns (uint256);
```

