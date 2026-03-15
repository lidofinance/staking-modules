# IVEBO
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IVEBO.sol)


## Functions
### SUBMIT_DATA_ROLE


```solidity
function SUBMIT_DATA_ROLE() external view returns (bytes32);
```

### getRoleMember


```solidity
function getRoleMember(bytes32 role, uint256 index) external view returns (address);
```

### grantRole


```solidity
function grantRole(bytes32 role, address account) external;
```

### getConsensusVersion


```solidity
function getConsensusVersion() external view returns (uint256);
```

### getContractVersion


```solidity
function getContractVersion() external view returns (uint256);
```

### getConsensusContract


```solidity
function getConsensusContract() external view returns (address);
```

### getConsensusReport


```solidity
function getConsensusReport()
    external
    view
    returns (bytes32 hash, uint256 refSlot, uint256 processingDeadlineTime, bool processingStarted);
```

### submitConsensusReport


```solidity
function submitConsensusReport(bytes32 reportHash, uint256 refSlot, uint256 deadline) external;
```

### submitReportData


```solidity
function submitReportData(ReportData calldata data, uint256 contractVersion) external;
```

## Structs
### ReportData

```solidity
struct ReportData {
    ///
    /// Oracle consensus info
    ///

    /// @dev Version of the oracle consensus rules. Current version expected
    /// by the oracle can be obtained by calling getConsensusVersion().
    uint256 consensusVersion;
    /// @dev Reference slot for which the report was calculated. If the slot
    /// contains a block, the state being reported should include all state
    /// changes resulting from that block. The epoch containing the slot
    /// should be finalized prior to calculating the report.
    uint256 refSlot;
    ///
    /// Requests data
    ///

    /// @dev Total number of validator exit requests in this report. Must not be greater
    /// than limit checked in OracleReportSanityChecker.checkExitBusOracleReport.
    uint256 requestsCount;
    /// @dev Format of the validator exit requests data. Currently, only the
    /// DATA_FORMAT_LIST=1 is supported.
    uint256 dataFormat;
    /// @dev Validator exit requests data. Can differ based on the data format,
    /// see the constant defining a specific data format below for more info.
    bytes data;
}
```

