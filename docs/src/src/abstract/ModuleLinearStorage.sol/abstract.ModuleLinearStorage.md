# ModuleLinearStorage
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/abstract/ModuleLinearStorage.sol)


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
    mapping(uint256 priority => DepositQueueLib.Queue queue) depositQueueByPriority;
    bytes32 freeSlot1;
    uint256 upToDateOperatorDepositInfoCount;
    /// @dev Total number of withdrawn validators reported for the module.
    uint256 totalWithdrawnValidators;
    mapping(uint256 noKeyIndexPacked => uint256) keyAddedBalances;
    uint256 nonce;
    mapping(uint256 nodeOperatorId => NodeOperator) nodeOperators;
    /// @dev see KeyPointerLib.keyPointer function for details of noKeyIndexPacked structure
    mapping(uint256 noKeyIndexPacked => bool) isValidatorWithdrawn;
    mapping(uint256 noKeyIndexPacked => bool) isValidatorSlashed;
    uint64 totalDepositedValidators;
    uint64 totalExitedValidators;
    uint64 depositableValidatorsCount;
    uint64 nodeOperatorsCount;
}
```

