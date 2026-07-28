# ILido
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/ILido.sol)

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

