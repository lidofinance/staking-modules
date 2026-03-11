# ValidatorCountsReport
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/ValidatorCountsReport.sol)

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

