# ParametersRegistry
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/ParametersRegistry.sol)

**Inherits:**
[IParametersRegistry](/src/interfaces/IParametersRegistry.sol/interface.IParametersRegistry.md), Initializable, AccessControlEnumerableUpgradeable

There are no upper limit checks except for the basis points (BP) values
since with the introduction of Dual Governance any malicious changes to the parameters can be objected by stETH holders.


## State Variables
### INITIALIZED_VERSION

```solidity
uint64 internal constant INITIALIZED_VERSION = 3
```


### MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE

```solidity
bytes32 public constant MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE =
    keccak256("MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE")
```


### MANAGE_KEYS_LIMIT_ROLE

```solidity
bytes32 public constant MANAGE_KEYS_LIMIT_ROLE = keccak256("MANAGE_KEYS_LIMIT_ROLE")
```


### MANAGE_QUEUE_CONFIG_ROLE

```solidity
bytes32 public constant MANAGE_QUEUE_CONFIG_ROLE = keccak256("MANAGE_QUEUE_CONFIG_ROLE")
```


### MANAGE_PERFORMANCE_PARAMETERS_ROLE

```solidity
bytes32 public constant MANAGE_PERFORMANCE_PARAMETERS_ROLE = keccak256("MANAGE_PERFORMANCE_PARAMETERS_ROLE")
```


### MANAGE_REWARD_SHARE_ROLE

```solidity
bytes32 public constant MANAGE_REWARD_SHARE_ROLE = keccak256("MANAGE_REWARD_SHARE_ROLE")
```


### MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE

```solidity
bytes32 public constant MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE = keccak256("MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE")
```


### MANAGE_CURVE_PARAMETERS_ROLE

```solidity
bytes32 public constant MANAGE_CURVE_PARAMETERS_ROLE = keccak256("MANAGE_CURVE_PARAMETERS_ROLE")
```


### MAX_BP
Maximal value for basis points (BP)
1 BP = 0.01%


```solidity
uint256 internal constant MAX_BP = 10000
```


### QUEUE_LOWEST_PRIORITY
QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].
Unused in CuratedModule.sol


```solidity
uint256 public immutable QUEUE_LOWEST_PRIORITY
```


### defaultKeyRemovalCharge
Key removal charge is not used in Curated Module


```solidity
uint256 public defaultKeyRemovalCharge
```


### _keyRemovalCharges

```solidity
mapping(uint256 curveId => MarkedUint248) internal _keyRemovalCharges
```


### defaultGeneralDelayedPenaltyAdditionalFine

```solidity
uint256 public defaultGeneralDelayedPenaltyAdditionalFine
```


### _generalDelayedPenaltyAdditionalFines

```solidity
mapping(uint256 curveId => MarkedUint248) internal _generalDelayedPenaltyAdditionalFines
```


### defaultKeysLimit

```solidity
uint256 public defaultKeysLimit
```


### _keysLimits

```solidity
mapping(uint256 curveId => MarkedUint248) internal _keysLimits
```


### defaultQueueConfig
Queue config is not used in Curated Module


```solidity
QueueConfig public defaultQueueConfig
```


### _queueConfigs

```solidity
mapping(uint256 curveId => QueueConfig) internal _queueConfigs
```


### defaultRewardShare
Default value for the reward share. Can only be set as a flat value due to possible sybil attacks
Decreased reward share for some validators > N will promote sybils. Increased reward share for validators > N will give large operators an advantage


```solidity
uint256 public defaultRewardShare
```


### _rewardShareData

```solidity
mapping(uint256 curveId => KeyNumberValueInterval[]) internal _rewardShareData
```


### defaultPerformanceLeeway
Default value for the performance leeway. Can only be set as a flat value due to possible sybil attacks
Decreased performance leeway for some validators > N will promote sybils. Increased performance leeway for validators > N will give large operators an advantage


```solidity
uint256 public defaultPerformanceLeeway
```


### _performanceLeewayData

```solidity
mapping(uint256 curveId => KeyNumberValueInterval[]) internal _performanceLeewayData
```


### defaultStrikesParams

```solidity
StrikesParams public defaultStrikesParams
```


### _strikesParams

```solidity
mapping(uint256 curveId => StrikesParams) internal _strikesParams
```


### defaultBadPerformancePenalty

```solidity
uint256 public defaultBadPerformancePenalty
```


### _badPerformancePenalties

```solidity
mapping(uint256 curveId => MarkedUint248) internal _badPerformancePenalties
```


### defaultPerformanceCoefficients

```solidity
PerformanceCoefficients public defaultPerformanceCoefficients
```


### _performanceCoefficients

```solidity
mapping(uint256 curveId => PerformanceCoefficients) internal _performanceCoefficients
```


### defaultAllowedExitDelay

```solidity
uint256 public defaultAllowedExitDelay
```


### _allowedExitDelay

```solidity
mapping(uint256 => uint256) internal _allowedExitDelay
```


### defaultExitDelayFee

```solidity
uint256 public defaultExitDelayFee
```


### _exitDelayFees

```solidity
mapping(uint256 => MarkedUint248) internal _exitDelayFees
```


### defaultMaxElWithdrawalRequestFee

```solidity
uint256 public defaultMaxElWithdrawalRequestFee
```


### _maxElWithdrawalRequestFees

```solidity
mapping(uint256 => MarkedUint248) internal _maxElWithdrawalRequestFees
```


## Functions
### onlyRoleMemberOrAdmin


```solidity
modifier onlyRoleMemberOrAdmin(bytes32 role) ;
```

### onlyRoleMemberOrCurveParametersRoleOrAdmin


```solidity
modifier onlyRoleMemberOrCurveParametersRoleOrAdmin(bytes32 role) ;
```

### constructor


```solidity
constructor(uint256 queueLowestPriority) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`queueLowestPriority`|`uint256`|The lowest priority value for the queue. Set to 0 for modules that don't use queue priorities.|


### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(address admin, InitializationData calldata data) external reinitializer(INITIALIZED_VERSION);
```

### finalizeUpgradeV3

This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing
version 2 deployment. If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.


```solidity
function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION);
```

### setDefaultKeyRemovalCharge

Set default value for the key removal charge. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module


```solidity
function setDefaultKeyRemovalCharge(uint256 keyRemovalCharge)
    external
    onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyRemovalCharge`|`uint256`|value to be set as default for the key removal charge|


### setDefaultGeneralDelayedPenaltyAdditionalFine

Set default value for the general delayed penalty additional fine. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultGeneralDelayedPenaltyAdditionalFine(uint256 fine)
    external
    onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fine`|`uint256`|value to be set as default for the general delayed penalty additional fine|


### setDefaultKeysLimit

Set default value for the keys limit. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultKeysLimit(uint256 limit) external onlyRoleMemberOrAdmin(MANAGE_KEYS_LIMIT_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|value to be set as default for the keys limit|


### setDefaultQueueConfig

Set default value for QueueConfig. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module


```solidity
function setDefaultQueueConfig(uint256 priority, uint256 maxDeposits)
    external
    onlyRoleMemberOrAdmin(MANAGE_QUEUE_CONFIG_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`priority`|`uint256`|Queue priority.|
|`maxDeposits`|`uint256`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### setDefaultRewardShare

Set default value for the reward share. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultRewardShare(uint256 share) external onlyRoleMemberOrAdmin(MANAGE_REWARD_SHARE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`share`|`uint256`|value to be set as default for the reward share|


### setDefaultPerformanceLeeway

Set default value for the performance leeway. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultPerformanceLeeway(uint256 leeway)
    external
    onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`leeway`|`uint256`|value to be set as default for the performance leeway|


### setDefaultStrikesParams

Set default values for the strikes lifetime and threshold. Default values are used if specific values are not set for the curveId


```solidity
function setDefaultStrikesParams(uint256 lifetime, uint256 threshold)
    external
    onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lifetime`|`uint256`|The default number of Performance Oracle frames to store strikes values|
|`threshold`|`uint256`|The default strikes value leading to validator force ejection.|


### setDefaultBadPerformancePenalty

Set the default value for the bad performance penalty for a single 32 ether validator
This value is used if a specific value is not set for the curveId


```solidity
function setDefaultBadPerformancePenalty(uint256 penalty)
    external
    onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`penalty`|`uint256`|value to be set as default for the bad performance penalty|


### setDefaultPerformanceCoefficients

Set default values for the performance coefficients. Default values are used if specific values are not set for the curveId


```solidity
function setDefaultPerformanceCoefficients(uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight)
    external
    onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`attestationsWeight`|`uint256`|value to be set as default for the attestations effectiveness weight|
|`blocksWeight`|`uint256`|value to be set as default for block proposals effectiveness weight|
|`syncWeight`|`uint256`|value to be set as default for sync participation effectiveness weight|


### setDefaultAllowedExitDelay

set default value for the allowed exit delay in seconds. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultAllowedExitDelay(uint256 delay)
    external
    onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`delay`|`uint256`|value to be set as default for the allowed exit delay|


### setDefaultExitDelayFee

Set the default value for exit delay penalty for a single 32 ether validator
This value is used if a specific value is not set for the curveId


```solidity
function setDefaultExitDelayFee(uint256 penalty)
    external
    onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`penalty`|`uint256`||


### setDefaultMaxElWithdrawalRequestFee

set default value for max EL withdrawal request fee. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultMaxElWithdrawalRequestFee(uint256 fee)
    external
    onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|value to be set as default for the max EL withdrawal request fee|


### setKeyRemovalCharge

Set key removal charge for the curveId. This parameter is not used in Curated Module


```solidity
function setKeyRemovalCharge(uint256 curveId, uint256 keyRemovalCharge)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate key removal charge with|
|`keyRemovalCharge`|`uint256`|Key removal charge|


### setGeneralDelayedPenaltyAdditionalFine

Set general delayed penalty additional fine for the curveId.


```solidity
function setGeneralDelayedPenaltyAdditionalFine(uint256 curveId, uint256 fine)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate general delayed penalty additional fine limit with|
|`fine`|`uint256`|General delayed penalty additional fine|


### setKeysLimit

Set keys limit for the curveId.


```solidity
function setKeysLimit(uint256 curveId, uint256 limit)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_KEYS_LIMIT_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate keys limit with|
|`limit`|`uint256`|Keys limit|


### setQueueConfig

Sets the provided config to the given curve. This parameter is not used in Curated Module


```solidity
function setQueueConfig(uint256 curveId, uint256 priority, uint256 maxDeposits)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_QUEUE_CONFIG_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to set the config.|
|`priority`|`uint256`|Queue priority.|
|`maxDeposits`|`uint256`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### setRewardShareData

Set reward share parameters for the curveId

KeyNumberValueInterval = [[1, 10000], [11, 8000], [51, 5000]] stands for
100% rewards for the first 10 keys, 80% rewards for the keys 11-50, and 50% rewards for the keys > 50


```solidity
function setRewardShareData(uint256 curveId, KeyNumberValueInterval[] calldata data)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_REWARD_SHARE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate reward share data with|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and reward share percentages in BP (ex. [[1, 10000], [11, 8000], [51, 5000]])|


### setPerformanceLeewayData

Set performance leeway parameters for the curveId

KeyNumberValueInterval = [[1, 500], [101, 450], [501, 400]] stands for
5% performance leeway for the first 100 keys, 4.5% performance leeway for the keys 101-500, and 4% performance leeway for the keys > 500


```solidity
function setPerformanceLeewayData(uint256 curveId, KeyNumberValueInterval[] calldata data)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance leeway data with|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and performance leeway percentages in BP (ex. [[1, 500], [101, 450], [501, 400]])|


### setStrikesParams

Set performance strikes lifetime and threshold for the curveId


```solidity
function setStrikesParams(uint256 curveId, uint256 lifetime, uint256 threshold)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance strikes lifetime and threshold with|
|`lifetime`|`uint256`|Number of Performance Oracle frames to store strikes values|
|`threshold`|`uint256`|The strikes value leading to validator force ejection|


### setBadPerformancePenalty

Set the bad performance penalty for the curveId for a single 32 ether validator


```solidity
function setBadPerformancePenalty(uint256 curveId, uint256 penalty)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate bad performance penalty with|
|`penalty`|`uint256`|Bad performance penalty|


### setPerformanceCoefficients

Set performance coefficients for the curveId


```solidity
function setPerformanceCoefficients(
    uint256 curveId,
    uint256 attestationsWeight,
    uint256 blocksWeight,
    uint256 syncWeight
) external onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance coefficients with|
|`attestationsWeight`|`uint256`|Attestations effectiveness weight|
|`blocksWeight`|`uint256`|Block proposals effectiveness weight|
|`syncWeight`|`uint256`|Sync participation effectiveness weight|


### setAllowedExitDelay

Set allowed exit delay for the curveId in seconds


```solidity
function setAllowedExitDelay(uint256 curveId, uint256 delay)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate allowed exit delay with|
|`delay`|`uint256`|allowed exit delay|


### setExitDelayFee

Set the exit delay penalty for a single 32 ether validator for the given curveId


```solidity
function setExitDelayFee(uint256 curveId, uint256 penalty)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate exit delay penalty with|
|`penalty`|`uint256`||


### setMaxElWithdrawalRequestFee

Set max EL withdrawal request fee for the curveId


```solidity
function setMaxElWithdrawalRequestFee(uint256 curveId, uint256 fee)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate max EL withdrawal request fee with|
|`fee`|`uint256`|Max EL withdrawal request fee|


### unsetKeyRemovalCharge

Unset key removal charge for the curveId. This parameter is not used in Curated Module


```solidity
function unsetKeyRemovalCharge(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom key removal charge for|


### unsetGeneralDelayedPenaltyAdditionalFine

Unset general delayed penalty additional fine for the curveId


```solidity
function unsetGeneralDelayedPenaltyAdditionalFine(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom general delayed penalty additional fine for|


### unsetKeysLimit

Unset keys limit for the curveId


```solidity
function unsetKeysLimit(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_KEYS_LIMIT_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom keys limit for|


### unsetQueueConfig

Set the given curve's config to the default one. This parameter is not used in Curated Module


```solidity
function unsetQueueConfig(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_QUEUE_CONFIG_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom config.|


### unsetRewardShareData

Unset reward share parameters for the curveId


```solidity
function unsetRewardShareData(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_REWARD_SHARE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom reward share parameters for|


### unsetPerformanceLeewayData

Unset performance leeway parameters for the curveId


```solidity
function unsetPerformanceLeewayData(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance leeway parameters for|


### unsetStrikesParams

Unset custom performance strikes lifetime and threshold for the curveId


```solidity
function unsetStrikesParams(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance strikes lifetime and threshold for|


### unsetBadPerformancePenalty

Unset bad performance penalty for the curveId


```solidity
function unsetBadPerformancePenalty(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom bad performance penalty for|


### unsetPerformanceCoefficients

Unset custom performance coefficients for the curveId


```solidity
function unsetPerformanceCoefficients(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance coefficients for|


### unsetAllowedExitDelay

Unset allowed exit delay for the curveId


```solidity
function unsetAllowedExitDelay(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset allowed exit delay for|


### unsetExitDelayFee

Unset exit delay penalty for the curveId


```solidity
function unsetExitDelayFee(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|The curve ID for unsetting the exit delay fee|


### unsetMaxElWithdrawalRequestFee

Unset max EL withdrawal request fee for the curveId


```solidity
function unsetMaxElWithdrawalRequestFee(uint256 curveId)
    external
    onlyRoleMemberOrCurveParametersRoleOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset max EL withdrawal request fee for|


### getKeyRemovalCharge

Get key removal charge by the curveId. A charge is taken from the bond for each removed key from the module. This parameter is not used in Curated Module

`defaultKeyRemovalCharge` is returned if the value is not set for the given curveId.


```solidity
function getKeyRemovalCharge(uint256 curveId) external view returns (uint256 keyRemovalCharge);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get key removal charge for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`keyRemovalCharge`|`uint256`|Key removal charge|


### getGeneralDelayedPenaltyAdditionalFine

Get general delayed penalty additional fine by the curveId. Additional fine is added to the general delayed penalty by CSM

`defaultGeneralDelayedPenaltyAdditionalFine` is returned if the value is not set for the given curveId.


```solidity
function getGeneralDelayedPenaltyAdditionalFine(uint256 curveId) external view returns (uint256 fine);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get general delayed penalty additional fine for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fine`|`uint256`|General delayed penalty additional fine|


### getKeysLimit

Get keys limit by the curveId. A limit indicates the maximal amount of the non-exited keys Node Operator can upload

`defaultKeysLimit` is returned if the value is not set for the given curveId.


```solidity
function getKeysLimit(uint256 curveId) external view returns (uint256 limit);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get keys limit for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|Keys limit|


### getQueueConfig

Get the queue config for the given curve. This parameter is not used in Curated Module


```solidity
function getQueueConfig(uint256 curveId) external view returns (uint32 queuePriority, uint32 maxDeposits);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get the queue config for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`queuePriority`|`uint32`|priority Queue priority.|
|`maxDeposits`|`uint32`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### getRewardShareData

Get reward share parameters by the curveId.

Returns [[1, defaultRewardShare]] if no intervals are set for the given curveId.


```solidity
function getRewardShareData(uint256 curveId) external view returns (KeyNumberValueInterval[] memory data);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get reward share data for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and reward share percentages in BP (ex. [[1, 10000], [11, 8000], [51, 5000]])|


### getPerformanceLeewayData

Get performance leeway parameters by the curveId

Returns [[1, defaultPerformanceLeeway]] if no intervals are set for the given curveId.


```solidity
function getPerformanceLeewayData(uint256 curveId) external view returns (KeyNumberValueInterval[] memory data);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get performance leeway data for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and performance leeway percentages in BP (ex. [[1, 500], [101, 450], [501, 400]])|


### getStrikesParams

Get performance strikes lifetime and threshold by the curveId

`defaultStrikesParams` are returned if the value is not set for the given curveId


```solidity
function getStrikesParams(uint256 curveId) external view returns (uint256 lifetime, uint256 threshold);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get performance strikes lifetime and threshold for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lifetime`|`uint256`|Number of Performance Oracle frames to store strikes values|
|`threshold`|`uint256`|The strikes value leading to validator force ejection|


### getBadPerformancePenalty

Get bad performance penalty for a single 32 ether validator by the curveId

`defaultBadPerformancePenalty` is returned if the value is not set for the given curveId.


```solidity
function getBadPerformancePenalty(uint256 curveId) external view returns (uint256 penalty);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get bad performance penalty for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`penalty`|`uint256`|Bad performance penalty|


### getPerformanceCoefficients

Get performance coefficients by the curveId

`defaultPerformanceCoefficients` are returned if the value is not set for the given curveId.


```solidity
function getPerformanceCoefficients(uint256 curveId)
    external
    view
    returns (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get performance coefficients for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`attestationsWeight`|`uint256`|Attestations effectiveness weight|
|`blocksWeight`|`uint256`|Block proposals effectiveness weight|
|`syncWeight`|`uint256`|Sync participation effectiveness weight|


### getAllowedExitDelay

Get allowed exit delay by the curveId in seconds

`defaultAllowedExitDelay` is returned if the value is not set for the given curveId.


```solidity
function getAllowedExitDelay(uint256 curveId) external view returns (uint256 delay);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get allowed exit delay for|


### getExitDelayFee

Get exit delay penalty for a single 32 ether validator by the curveId

`defaultExitDelayFee` is returned if the value is not set for the given curveId.


```solidity
function getExitDelayFee(uint256 curveId) external view returns (uint256 penalty);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve ID to get the exit delay fee for|


### getMaxElWithdrawalRequestFee

Get max EL withdrawal request fee by the curveId

`defaultMaxElWithdrawalRequestFee` is returned if the value is not set for the given curveId.


```solidity
function getMaxElWithdrawalRequestFee(uint256 curveId) external view returns (uint256 fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get max EL withdrawal request fee for|


### getCurveParameters

Get all parameters resolved for the given curveId in one call

Per-curve values are returned where set, otherwise defaults are used


```solidity
function getCurveParameters(uint256 curveId) external view returns (CurveParameters memory params);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get all parameters for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`params`|`CurveParameters`|All resolved parameters for the given curveId|


### getInitializedVersion

Returns the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

### _setDefaultKeyRemovalCharge


```solidity
function _setDefaultKeyRemovalCharge(uint256 keyRemovalCharge) internal;
```

### _setDefaultGeneralDelayedPenaltyAdditionalFine


```solidity
function _setDefaultGeneralDelayedPenaltyAdditionalFine(uint256 fine) internal;
```

### _setDefaultKeysLimit


```solidity
function _setDefaultKeysLimit(uint256 limit) internal;
```

### _setDefaultRewardShare


```solidity
function _setDefaultRewardShare(uint256 share) internal;
```

### _setDefaultPerformanceLeeway


```solidity
function _setDefaultPerformanceLeeway(uint256 leeway) internal;
```

### _setDefaultStrikesParams


```solidity
function _setDefaultStrikesParams(uint256 lifetime, uint256 threshold) internal;
```

### _setDefaultBadPerformancePenalty


```solidity
function _setDefaultBadPerformancePenalty(uint256 penalty) internal;
```

### _setDefaultPerformanceCoefficients


```solidity
function _setDefaultPerformanceCoefficients(uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight)
    internal;
```

### _setDefaultQueueConfig


```solidity
function _setDefaultQueueConfig(uint256 priority, uint256 maxDeposits) internal;
```

### _setDefaultAllowedExitDelay


```solidity
function _setDefaultAllowedExitDelay(uint256 delay) internal;
```

### _setDefaultExitDelayFee


```solidity
function _setDefaultExitDelayFee(uint256 penalty) internal;
```

### _setDefaultMaxElWithdrawalRequestFee


```solidity
function _setDefaultMaxElWithdrawalRequestFee(uint256 fee) internal;
```

### _getKeyRemovalCharge


```solidity
function _getKeyRemovalCharge(uint256 curveId) internal view returns (uint256);
```

### _getGeneralDelayedPenaltyAdditionalFine


```solidity
function _getGeneralDelayedPenaltyAdditionalFine(uint256 curveId) internal view returns (uint256);
```

### _getKeysLimit


```solidity
function _getKeysLimit(uint256 curveId) internal view returns (uint256);
```

### _getQueueConfig


```solidity
function _getQueueConfig(uint256 curveId) internal view returns (uint32, uint32);
```

### _getRewardShareData


```solidity
function _getRewardShareData(uint256 curveId) internal view returns (KeyNumberValueInterval[] memory data);
```

### _getPerformanceLeewayData


```solidity
function _getPerformanceLeewayData(uint256 curveId) internal view returns (KeyNumberValueInterval[] memory data);
```

### _getStrikesParams


```solidity
function _getStrikesParams(uint256 curveId) internal view returns (uint256, uint256);
```

### _getBadPerformancePenalty


```solidity
function _getBadPerformancePenalty(uint256 curveId) internal view returns (uint256);
```

### _getPerformanceCoefficients


```solidity
function _getPerformanceCoefficients(uint256 curveId) internal view returns (uint256, uint256, uint256);
```

### _getAllowedExitDelay


```solidity
function _getAllowedExitDelay(uint256 curveId) internal view returns (uint256 delay);
```

### _getExitDelayFee


```solidity
function _getExitDelayFee(uint256 curveId) internal view returns (uint256);
```

### _getMaxElWithdrawalRequestFee


```solidity
function _getMaxElWithdrawalRequestFee(uint256 curveId) internal view returns (uint256);
```

### _onlyRoleMemberOrAdmin


```solidity
function _onlyRoleMemberOrAdmin(bytes32 role) internal view;
```

### _onlyRoleMemberOrCurveParametersRoleOrAdmin


```solidity
function _onlyRoleMemberOrCurveParametersRoleOrAdmin(bytes32 role) internal view;
```

### _validateQueueConfig


```solidity
function _validateQueueConfig(uint256 priority, uint256 maxDeposits) internal view;
```

### _validateStrikesParams


```solidity
function _validateStrikesParams(uint256 lifetime, uint256 threshold) internal pure;
```

### _validateAllowedExitDelay


```solidity
function _validateAllowedExitDelay(uint256 delay) internal pure;
```

### _validatePerformanceCoefficients


```solidity
function _validatePerformanceCoefficients(uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight)
    internal
    pure;
```

### _validateKeyNumberValueIntervals


```solidity
function _validateKeyNumberValueIntervals(KeyNumberValueInterval[] calldata intervals) private pure;
```

