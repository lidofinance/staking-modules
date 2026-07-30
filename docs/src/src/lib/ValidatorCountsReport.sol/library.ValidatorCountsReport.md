# ValidatorCountsReport
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/ValidatorCountsReport.sol)

**Author:**
skhomuti


## Functions
### safeCountOperators


```solidity
function safeCountOperators(bytes calldata ids, bytes calldata counts) internal pure returns (uint256 len);
```

### next


```solidity
function next(bytes calldata ids, bytes calldata counts, uint256 offset)
    internal
    pure
    returns (uint256 nodeOperatorId, uint256 keysCount);
```

## Errors
### InvalidReportData

```solidity
error InvalidReportData();
```

