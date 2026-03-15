# ILido
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/ILido.sol)

**Inherits:**
[IStETH](/src/interfaces/IStETH.sol/interface.IStETH.md)

**Title:**
Interface defining Lido contract


## Functions
### STAKING_CONTROL_ROLE


```solidity
function STAKING_CONTROL_ROLE() external view returns (bytes32);
```

### submit


```solidity
function submit(address _referral) external payable returns (uint256);
```

### getDepositableEther


```solidity
function getDepositableEther() external view returns (uint256);
```

### removeStakingLimit


```solidity
function removeStakingLimit() external;
```

### kernel


```solidity
function kernel() external returns (address);
```

### sharesOf


```solidity
function sharesOf(address _account) external view returns (uint256);
```

