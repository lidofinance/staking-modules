# ModuleLinearStorage
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/abstract/ModuleLinearStorage.sol)


## Functions
### _baseStorage


```solidity
function _baseStorage() internal pure returns (BaseModuleStorage storage $);
```

## Structs
### BaseModuleStorage
Linear storage layout of the module. All state lives in a single struct
accessed via `_baseStorage()` at slot 0.


```solidity
struct BaseModuleStorage {
    /// @dev Having this mapping here to preserve the current layout of the storage of the CSModule.
    /* 0 */ mapping(uint256 priority => DepositQueueLib.Queue queue) depositQueueByPriority;
    /// @dev Total number of withdrawn validators reported for the module.
    /* 1 */ uint256 totalWithdrawnValidators;
    /* 2 */ uint256 upToDateOperatorDepositInfoCount; /// XXX: the slot was used as a mapping in CSM v1 and v2.
    /* 3 */ mapping(uint256 noKeyIndexPacked => uint256) keyAllocatedBalance;
    /* 4 */ mapping(uint256 noKeyIndexPacked => uint256) keyConfirmedBalance;
    /* 5 */ uint256 nonce;
    /* 6 */ mapping(uint256 nodeOperatorId => NodeOperator) nodeOperators;
    /// @dev see KeyPointerLib.keyPointer function for details of noKeyIndexPacked structure
    /* 7 */ mapping(uint256 noKeyIndexPacked => bool) isValidatorWithdrawn;
    /* 8 */ mapping(uint256 noKeyIndexPacked => bool) isValidatorSlashed;
    /* 9 */ uint64 totalDepositedValidators;
    /* 9 */ uint64 totalExitedValidators;
    /* 9 */ uint64 depositableValidatorsCount;
    /* 9 */ uint64 nodeOperatorsCount;
    /* 10 */ mapping(uint256 nodeOperatorId => uint256 extraBalance) operatorBalances;
    /* 11 */ uint256 totalExtraStake;
}
```

