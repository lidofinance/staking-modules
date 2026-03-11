# IFeeOracle
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IFeeOracle.sol)

**Inherits:**
[IAssetRecovererLib](/src/lib/AssetRecovererLib.sol/interface.IAssetRecovererLib.md)


## Functions
### SUBMIT_DATA_ROLE


```solidity
function SUBMIT_DATA_ROLE() external view returns (bytes32);
```

### FEE_DISTRIBUTOR


```solidity
function FEE_DISTRIBUTOR() external view returns (IFeeDistributor);
```

### STRIKES


```solidity
function STRIKES() external view returns (IValidatorStrikes);
```

### submitReportData

Submit the data for a committee report


```solidity
function submitReportData(ReportData calldata data, uint256 contractVersion) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ReportData`|Data for a committee report|
|`contractVersion`|`uint256`|Expected storage contract version of the FeeOracle implementation|


## Errors
### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### ZeroFeeDistributorAddress

```solidity
error ZeroFeeDistributorAddress();
```

### ZeroStrikesAddress

```solidity
error ZeroStrikesAddress();
```

### SenderNotAllowed

```solidity
error SenderNotAllowed();
```

## Structs
### ReportData

```solidity
struct ReportData {
    /// @dev Version of the oracle consensus rules. Current version expected
    /// by the oracle can be obtained by calling getConsensusVersion().
    uint256 consensusVersion;
    /// @dev Reference slot for which the report was calculated. If the slot
    /// contains a block, the state being reported should include all state
    /// changes resulting from that block. The epoch containing the slot
    /// should be finalized prior to calculating the report.
    uint256 refSlot;
    /// @notice Merkle Tree root.
    bytes32 treeRoot;
    /// @notice CID of the published Merkle tree.
    string treeCid;
    /// @notice CID of the file with log of the frame reported.
    string logCid;
    /// @notice Total amount of fees distributed in the report.
    uint256 distributed;
    /// @notice Amount of the rebate shares in the report
    uint256 rebate;
    /// @notice Merkle Tree root of the strikes.
    bytes32 strikesTreeRoot;
    /// @notice CID of the published Merkle tree of the strikes.
    string strikesTreeCid;
}
```

