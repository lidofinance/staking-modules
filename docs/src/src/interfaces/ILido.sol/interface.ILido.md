# ILido
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/interfaces/ILido.sol)

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

