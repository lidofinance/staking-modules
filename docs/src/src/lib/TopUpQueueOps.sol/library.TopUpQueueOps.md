# TopUpQueueOps
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/TopUpQueueOps.sol)

External deployment-linked library used by CSModule to reduce bytecode size.


## State Variables
### TOP_UP_STEP

```solidity
uint256 internal constant TOP_UP_STEP = 2 ether
```


## Functions
### allocateDeposits


```solidity
function allocateDeposits(
    TopUpQueueLib.Queue storage topUpQueue,
    uint256 maxDepositAmount,
    bytes[] calldata pubkeys,
    uint256[] calldata keyIndices,
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory);
```

### _allocateDeposits


```solidity
function _allocateDeposits(
    TopUpQueueLib.Queue storage topUpQueue,
    uint256 maxDepositAmount,
    bytes[] calldata pubkeys,
    TopUpKeyParams memory data
) private returns (uint256[] memory allocations);
```

### _quantizeAmount


```solidity
function _quantizeAmount(uint256 value) private pure returns (uint256 quantized);
```

## Structs
### TopUpKeyParams

```solidity
struct TopUpKeyParams {
    uint256[] keyIndices;
    uint256[] operatorIds;
    uint256[] topUpLimits;
}
```

