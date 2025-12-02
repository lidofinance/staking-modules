# FeeSplits
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/FeeSplits.sol)


## State Variables
### MAX_BP

```solidity
uint256 internal constant MAX_BP = 10_000
```


### MAX_FEE_SPLITS

```solidity
uint256 public constant MAX_FEE_SPLITS = 10
```


## Functions
### setFeeSplits


```solidity
function setFeeSplits(
    mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage,
    mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
    IFeeDistributor feeDistributor,
    uint256 nodeOperatorId,
    uint256 cumulativeFeeShares,
    bytes32[] calldata rewardsProof,
    IAccounting.FeeSplit[] calldata feeSplits
) external;
```

### splitAndTransferFees


```solidity
function splitAndTransferFees(
    mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage,
    mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
    ILido lido,
    uint256 nodeOperatorId,
    uint256 maxSharesToSplit
) external returns (uint256 transferred);
```

### hasSplits


```solidity
function hasSplits(mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage, uint256 nodeOperatorId)
    external
    view
    returns (bool);
```

