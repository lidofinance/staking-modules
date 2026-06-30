# ValidatorCountsReport
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/ValidatorCountsReport.sol)

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

