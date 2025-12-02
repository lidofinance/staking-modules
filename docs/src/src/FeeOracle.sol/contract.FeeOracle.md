# FeeOracle
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/FeeOracle.sol)

**Inherits:**
[IFeeOracle](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IFeeOracle.sol/interface.IFeeOracle.md), [BaseOracle](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/base-oracle/BaseOracle.sol/abstract.BaseOracle.md), [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)


## State Variables
### SUBMIT_DATA_ROLE
No assets are stored in the contract

An ACL role granting the permission to submit the data for a committee report.


```solidity
bytes32 public constant SUBMIT_DATA_ROLE = keccak256("SUBMIT_DATA_ROLE")
```


### PAUSE_ROLE
An ACL role granting the permission to pause accepting oracle reports


```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE
An ACL role granting the permission to resume accepting oracle reports


```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


### RECOVERER_ROLE
An ACL role granting the permission to recover assets


```solidity
bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE")
```


### FEE_DISTRIBUTOR

```solidity
IFeeDistributor public immutable FEE_DISTRIBUTOR
```


### STRIKES

```solidity
IValidatorStrikes public immutable STRIKES
```


### _feeDistributor
DEPRECATED

**Note:**
oz-renamed-from: feeDistributor


```solidity
IFeeDistributor internal _feeDistributor
```


### _avgPerfLeewayBP
DEPRECATED

**Note:**
oz-renamed-from: avgPerfLeewayBP


```solidity
uint256 internal _avgPerfLeewayBP
```


## Functions
### constructor


```solidity
constructor(address feeDistributor, address strikes, uint256 secondsPerSlot, uint256 genesisTime)
    BaseOracle(secondsPerSlot, genesisTime);
```

### initialize

initialize contract from scratch


```solidity
function initialize(address admin, address consensusContract, uint256 consensusVersion) external;
```

### finalizeUpgradeV2

This method is expected to be called only when the contract is upgraded from version 1 to version 2 for the existing version 1 deployment.
If the version 2 contract is deployed from scratch, the `initialize` method should be used instead.


```solidity
function finalizeUpgradeV2(uint256 consensusVersion) external;
```

### resume

Resume accepting oracle reports


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause accepting oracle reports for a `duration` seconds


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### submitReportData

Submit the data for a committee report


```solidity
function submitReportData(ReportData calldata data, uint256 contractVersion) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ReportData`|Data for a committee report|
|`contractVersion`|`uint256`|Version of the oracle consensus rules|


### _handleConsensusReport

Called in `submitConsensusReport` after a consensus is reached.


```solidity
function _handleConsensusReport(
    ConsensusReport memory,
    /* report */
    uint256,
    /* prevSubmittedRefSlot */
    uint256 /* prevProcessingRefSlot */
)
    internal
    override;
```

### _handleConsensusReportData


```solidity
function _handleConsensusReportData(ReportData calldata data) internal;
```

### _checkMsgSenderIsAllowedToSubmitData


```solidity
function _checkMsgSenderIsAllowedToSubmitData() internal view;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

