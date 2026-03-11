# FeeDistributor
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/FeeDistributor.sol)

**Inherits:**
[IFeeDistributor](/src/interfaces/IFeeDistributor.sol/interface.IFeeDistributor.md), Initializable, AccessControlEnumerableUpgradeable, [AssetRecoverer](/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)

**Author:**
madlabman


## State Variables
### INITIALIZED_VERSION

```solidity
uint64 internal constant INITIALIZED_VERSION = 3
```


### STETH

```solidity
IStETH public immutable STETH
```


### ACCOUNTING

```solidity
address public immutable ACCOUNTING
```


### ORACLE

```solidity
address public immutable ORACLE
```


### treeRoot
The latest Merkle Tree root


```solidity
bytes32 public treeRoot
```


### treeCid
CID of the last published Merkle tree


```solidity
string public treeCid
```


### logCid
CID of the file with log for the last frame reported


```solidity
string public logCid
```


### distributedShares
Amount of stETH shares sent to the Accounting in favor of the NO


```solidity
mapping(uint256 nodeOperatorId => uint256 distributed) public distributedShares
```


### totalClaimableShares
Total Amount of stETH shares available for claiming by NOs


```solidity
uint256 public totalClaimableShares
```


### _distributionDataHistory
Array of the distribution data history


```solidity
mapping(uint256 index => DistributionData) internal _distributionDataHistory
```


### distributionDataHistoryCount
The number of _distributionDataHistory records


```solidity
uint256 public distributionDataHistoryCount
```


### rebateRecipient
The address to transfer rebate to


```solidity
address public rebateRecipient
```


## Functions
### onlyAccounting


```solidity
modifier onlyAccounting() ;
```

### onlyOracle


```solidity
modifier onlyOracle() ;
```

### constructor


```solidity
constructor(address stETH, address accounting, address oracle) ;
```

### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(address admin, address _rebateRecipient) external reinitializer(INITIALIZED_VERSION);
```

### finalizeUpgradeV3

This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing
version 2 deployment. If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.


```solidity
function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION);
```

### setRebateRecipient

Set address to send rebate to


```solidity
function setRebateRecipient(address _rebateRecipient) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_rebateRecipient`|`address`|Address to send rebate to|


### distributeFees

Distribute fees to the Accounting in favor of the Node Operator


```solidity
function distributeFees(uint256 nodeOperatorId, uint256 cumulativeFeeShares, bytes32[] calldata proof)
    external
    onlyAccounting
    returns (uint256 sharesToDistribute);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`cumulativeFeeShares`|`uint256`|Total Amount of stETH shares earned as fees|
|`proof`|`bytes32[]`|Merkle proof of the leaf|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sharesToDistribute`|`uint256`|Amount of stETH shares distributed|


### processOracleReport

Receive the data of the Merkle tree from the Oracle contract and process it


```solidity
function processOracleReport(
    bytes32 _treeRoot,
    string calldata _treeCid,
    string calldata _logCid,
    uint256 distributed,
    uint256 rebate,
    uint256 refSlot
) external onlyOracle;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treeRoot`|`bytes32`|Root of the Merkle tree|
|`_treeCid`|`string`|an IPFS CID of the tree|
|`_logCid`|`string`|an IPFS CID of the log|
|`distributed`|`uint256`|an amount of the distributed shares|
|`rebate`|`uint256`|an amount of the rebate shares|
|`refSlot`|`uint256`|refSlot of the report|


### recoverERC20

Allows sender to recover ERC20 tokens held by the contract


```solidity
function recoverERC20(address token, uint256 amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to recover|
|`amount`|`uint256`|The amount of the ERC20 token to recover|


### getInitializedVersion

Get the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

### pendingSharesToDistribute

Get the Amount of stETH shares that are pending to be distributed


```solidity
function pendingSharesToDistribute() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|pendingShares Amount shares that are pending to distribute|


### getHistoricalDistributionData

Get the historical record of distribution data


```solidity
function getHistoricalDistributionData(uint256 index) external view returns (DistributionData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|Historical entry index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`DistributionData`|Historical distribution data|


### getFeesToDistribute

Get the Amount of stETH shares that can be distributed in favor of the Node Operator


```solidity
function getFeesToDistribute(uint256 nodeOperatorId, uint256 cumulativeFeeShares, bytes32[] calldata proof)
    public
    view
    returns (uint256 sharesToDistribute);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`cumulativeFeeShares`|`uint256`|Total Amount of stETH shares earned as fees|
|`proof`|`bytes32[]`|Merkle proof of the leaf|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sharesToDistribute`|`uint256`|Amount of stETH shares that can be distributed|


### hashLeaf

Get a hash of a leaf

Double hash the leaf to prevent second preimage attacks


```solidity
function hashLeaf(uint256 nodeOperatorId, uint256 shares) public pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`shares`|`uint256`|Amount of stETH shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash of the leaf|


### _setRebateRecipient


```solidity
function _setRebateRecipient(address _rebateRecipient) internal;
```

### _onlyAccounting


```solidity
function _onlyAccounting() internal view;
```

### _onlyOracle


```solidity
function _onlyOracle() internal view;
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

