# IParametersRegistry
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IParametersRegistry.sol)


## Functions
### MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE

Role to manage general penalties and charges parameters: key removal charge and general delayed penalty additional fine


```solidity
function MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE() external view returns (bytes32);
```

### MANAGE_KEYS_LIMIT_ROLE

Role to manage keys limit parameter


```solidity
function MANAGE_KEYS_LIMIT_ROLE() external view returns (bytes32);
```

### MANAGE_QUEUE_CONFIG_ROLE

Role to manage queue config


```solidity
function MANAGE_QUEUE_CONFIG_ROLE() external view returns (bytes32);
```

### MANAGE_PERFORMANCE_PARAMETERS_ROLE

Role to manage performance parameters: performance leeway, strikes params, bad performance penalty, performance coefficients


```solidity
function MANAGE_PERFORMANCE_PARAMETERS_ROLE() external view returns (bytes32);
```

### MANAGE_REWARD_SHARE_ROLE

Role to manage reward share parameters


```solidity
function MANAGE_REWARD_SHARE_ROLE() external view returns (bytes32);
```

### MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE

Role to manage validator exit related parameters: allowed exit delay, exit delay fee, EL max withdrawal request fee


```solidity
function MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE() external view returns (bytes32);
```

### MANAGE_CURVE_PARAMETERS_ROLE

Role to manage per-curve parameters (setters and unsetters only)


```solidity
function MANAGE_CURVE_PARAMETERS_ROLE() external view returns (bytes32);
```

### QUEUE_LOWEST_PRIORITY

The lowest priority a deposit queue can be assigned with. This constant is not used in Curated Module


```solidity
function QUEUE_LOWEST_PRIORITY() external view returns (uint256);
```

### defaultKeyRemovalCharge

Get default value for the key removal charge. This parameter is not used in Curated Module


```solidity
function defaultKeyRemovalCharge() external returns (uint256);
```

### defaultGeneralDelayedPenaltyAdditionalFine

Get default value for the general delayed penalty additional fine


```solidity
function defaultGeneralDelayedPenaltyAdditionalFine() external returns (uint256);
```

### defaultKeysLimit

Get default value for the keys limit


```solidity
function defaultKeysLimit() external returns (uint256);
```

### defaultQueueConfig

Get default value for QueueConfig. This parameter is not used in Curated Module


```solidity
function defaultQueueConfig() external returns (uint32 priority, uint32 maxDeposits);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`priority`|`uint32`|Default queue priority|
|`maxDeposits`|`uint32`|Default maximum number of the first deposits a Node Operator can get via the priority queue|


### defaultRewardShare

Get default value for the reward share


```solidity
function defaultRewardShare() external returns (uint256);
```

### defaultPerformanceLeeway

Get default value for the performance leeway


```solidity
function defaultPerformanceLeeway() external returns (uint256);
```

### defaultStrikesParams

Get default value for the strikes lifetime (frames count) and threshold (integer)


```solidity
function defaultStrikesParams() external returns (uint32 lifetime, uint32 threshold);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lifetime`|`uint32`|The default number of Performance Oracle frames to store strikes values|
|`threshold`|`uint32`|The default strikes value leading to validator force ejection.|


### defaultBadPerformancePenalty

Get default value for the bad performance penalty


```solidity
function defaultBadPerformancePenalty() external returns (uint256);
```

### defaultPerformanceCoefficients

Get default value for the performance coefficients


```solidity
function defaultPerformanceCoefficients()
    external
    returns (uint32 attestationsWeight, uint32 blocksWeight, uint32 syncWeight);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`attestationsWeight`|`uint32`|Attestations effectiveness weight|
|`blocksWeight`|`uint32`|Block proposals effectiveness weight|
|`syncWeight`|`uint32`|Sync participation effectiveness weight|


### defaultAllowedExitDelay

Get default value for the allowed exit delay


```solidity
function defaultAllowedExitDelay() external returns (uint256);
```

### defaultExitDelayFee

Get default value for exit delay penalty


```solidity
function defaultExitDelayFee() external returns (uint256);
```

### defaultMaxElWithdrawalRequestFee

Get default value for max EL withdrawal request fee


```solidity
function defaultMaxElWithdrawalRequestFee() external returns (uint256);
```

### setDefaultKeyRemovalCharge

Set default value for the key removal charge. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module


```solidity
function setDefaultKeyRemovalCharge(uint256 keyRemovalCharge) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyRemovalCharge`|`uint256`|value to be set as default for the key removal charge|


### setDefaultGeneralDelayedPenaltyAdditionalFine

Set default value for the general delayed penalty additional fine. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultGeneralDelayedPenaltyAdditionalFine(uint256 fine) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fine`|`uint256`|value to be set as default for the general delayed penalty additional fine|


### setDefaultKeysLimit

Set default value for the keys limit. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultKeysLimit(uint256 limit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|value to be set as default for the keys limit|


### setDefaultQueueConfig

Set default value for QueueConfig. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module


```solidity
function setDefaultQueueConfig(uint256 priority, uint256 maxDeposits) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`priority`|`uint256`|Queue priority.|
|`maxDeposits`|`uint256`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### setDefaultRewardShare

Set default value for the reward share. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultRewardShare(uint256 share) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`share`|`uint256`|value to be set as default for the reward share|


### setDefaultPerformanceLeeway

Set default value for the performance leeway. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultPerformanceLeeway(uint256 leeway) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`leeway`|`uint256`|value to be set as default for the performance leeway|


### setDefaultStrikesParams

Set default values for the strikes lifetime and threshold. Default values are used if specific values are not set for the curveId


```solidity
function setDefaultStrikesParams(uint256 lifetime, uint256 threshold) external;
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
function setDefaultBadPerformancePenalty(uint256 penalty) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`penalty`|`uint256`|value to be set as default for the bad performance penalty|


### setDefaultPerformanceCoefficients

Set default values for the performance coefficients. Default values are used if specific values are not set for the curveId


```solidity
function setDefaultPerformanceCoefficients(uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight)
    external;
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
function setDefaultAllowedExitDelay(uint256 delay) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`delay`|`uint256`|value to be set as default for the allowed exit delay|


### setDefaultExitDelayFee

Set the default value for exit delay penalty for a single 32 ether validator
This value is used if a specific value is not set for the curveId


```solidity
function setDefaultExitDelayFee(uint256 fee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|The value to be set as default for the exit delay fee|


### setDefaultMaxElWithdrawalRequestFee

set default value for max EL withdrawal request fee. Default value is used if a specific value is not set for the curveId


```solidity
function setDefaultMaxElWithdrawalRequestFee(uint256 fee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|value to be set as default for the max EL withdrawal request fee|


### setKeyRemovalCharge

Set key removal charge for the curveId. This parameter is not used in Curated Module


```solidity
function setKeyRemovalCharge(uint256 curveId, uint256 keyRemovalCharge) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate key removal charge with|
|`keyRemovalCharge`|`uint256`|Key removal charge|


### unsetKeyRemovalCharge

Unset key removal charge for the curveId. This parameter is not used in Curated Module


```solidity
function unsetKeyRemovalCharge(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom key removal charge for|


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


### setGeneralDelayedPenaltyAdditionalFine

Set general delayed penalty additional fine for the curveId.


```solidity
function setGeneralDelayedPenaltyAdditionalFine(uint256 curveId, uint256 fine) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate general delayed penalty additional fine limit with|
|`fine`|`uint256`|General delayed penalty additional fine|


### unsetGeneralDelayedPenaltyAdditionalFine

Unset general delayed penalty additional fine for the curveId


```solidity
function unsetGeneralDelayedPenaltyAdditionalFine(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom general delayed penalty additional fine for|


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


### setKeysLimit

Set keys limit for the curveId.


```solidity
function setKeysLimit(uint256 curveId, uint256 limit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate keys limit with|
|`limit`|`uint256`|Keys limit|


### unsetKeysLimit

Unset keys limit for the curveId


```solidity
function unsetKeysLimit(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom keys limit for|


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


### setQueueConfig

Sets the provided config to the given curve. This parameter is not used in Curated Module


```solidity
function setQueueConfig(uint256 curveId, uint256 priority, uint256 maxDeposits) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to set the config.|
|`priority`|`uint256`|Queue priority.|
|`maxDeposits`|`uint256`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### unsetQueueConfig

Set the given curve's config to the default one. This parameter is not used in Curated Module


```solidity
function unsetQueueConfig(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom config.|


### getQueueConfig

Get the queue config for the given curve. This parameter is not used in Curated Module


```solidity
function getQueueConfig(uint256 curveId) external view returns (uint32 priority, uint32 maxDeposits);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to get the queue config for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`priority`|`uint32`|Queue priority.|
|`maxDeposits`|`uint32`|Maximum number of the first deposits a Node Operator can get via the priority queue. Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue until the Node Operator has totalDepositedKeys + enqueued >= 10.|


### setRewardShareData

Set reward share parameters for the curveId

KeyNumberValueInterval = [[1, 10000], [11, 8000], [51, 5000]] stands for
100% rewards for the first 10 keys, 80% rewards for the keys 11-50, and 50% rewards for the keys > 50


```solidity
function setRewardShareData(uint256 curveId, KeyNumberValueInterval[] calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate reward share data with|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and reward share percentages in BP (ex. [[1, 10000], [11, 8000], [51, 5000]])|


### unsetRewardShareData

Unset reward share parameters for the curveId


```solidity
function unsetRewardShareData(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom reward share parameters for|


### getRewardShareData

Get reward share parameters by the curveId.

Returns [[1, defaultRewardShare]] if no intervals are set for the given curveId.

KeyNumberValueInterval = [[1, 10000], [11, 8000], [51, 5000]] stands for
100% rewards for the first 10 keys, 80% rewards for the keys 11-50, and 50% rewards for the keys > 50


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


### setPerformanceLeewayData

Set performance leeway parameters for the curveId

KeyNumberValueInterval = [[1, 500], [101, 450], [501, 400]] stands for
5% performance leeway for the first 100 keys, 4.5% performance leeway for the keys 101-500, and 4% performance leeway for the keys > 500


```solidity
function setPerformanceLeewayData(uint256 curveId, KeyNumberValueInterval[] calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance leeway data with|
|`data`|`KeyNumberValueInterval[]`|Interval values for keys count and performance leeway percentages in BP (ex. [[1, 500], [101, 450], [501, 400]])|


### unsetPerformanceLeewayData

Unset performance leeway parameters for the curveId


```solidity
function unsetPerformanceLeewayData(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance leeway parameters for|


### getPerformanceLeewayData

Get performance leeway parameters by the curveId

Returns [[1, defaultPerformanceLeeway]] if no intervals are set for the given curveId.

KeyNumberValueInterval = [[1, 500], [101, 450], [501, 400]] stands for
5% performance leeway for the first 100 keys, 4.5% performance leeway for the keys 101-500, and 4% performance leeway for the keys > 500


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


### setStrikesParams

Set performance strikes lifetime and threshold for the curveId


```solidity
function setStrikesParams(uint256 curveId, uint256 lifetime, uint256 threshold) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance strikes lifetime and threshold with|
|`lifetime`|`uint256`|Number of Performance Oracle frames to store strikes values|
|`threshold`|`uint256`|The strikes value leading to validator force ejection|


### unsetStrikesParams

Unset custom performance strikes lifetime and threshold for the curveId


```solidity
function unsetStrikesParams(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance strikes lifetime and threshold for|


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


### setBadPerformancePenalty

Set the bad performance penalty for the curveId for a single 32 ether validator


```solidity
function setBadPerformancePenalty(uint256 curveId, uint256 penalty) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate bad performance penalty with|
|`penalty`|`uint256`|Bad performance penalty|


### unsetBadPerformancePenalty

Unset bad performance penalty for the curveId


```solidity
function unsetBadPerformancePenalty(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom bad performance penalty for|


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


### setPerformanceCoefficients

Set performance coefficients for the curveId


```solidity
function setPerformanceCoefficients(
    uint256 curveId,
    uint256 attestationsWeight,
    uint256 blocksWeight,
    uint256 syncWeight
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate performance coefficients with|
|`attestationsWeight`|`uint256`|Attestations effectiveness weight|
|`blocksWeight`|`uint256`|Block proposals effectiveness weight|
|`syncWeight`|`uint256`|Sync participation effectiveness weight|


### unsetPerformanceCoefficients

Unset custom performance coefficients for the curveId


```solidity
function unsetPerformanceCoefficients(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset custom performance coefficients for|


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


### setAllowedExitDelay

Set allowed exit delay for the curveId in seconds


```solidity
function setAllowedExitDelay(uint256 curveId, uint256 delay) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate allowed exit delay with|
|`delay`|`uint256`|allowed exit delay|


### unsetAllowedExitDelay

Unset allowed exit delay for the curveId


```solidity
function unsetAllowedExitDelay(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset allowed exit delay for|


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


### setExitDelayFee

Set the exit delay penalty for a single 32 ether validator for the given curveId


```solidity
function setExitDelayFee(uint256 curveId, uint256 fee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate exit delay penalty with|
|`fee`|`uint256`|Exit delay fee|


### unsetExitDelayFee

Unset exit delay penalty for the curveId


```solidity
function unsetExitDelayFee(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|The curve ID for unsetting the exit delay fee|


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


### setMaxElWithdrawalRequestFee

Set max EL withdrawal request fee for the curveId


```solidity
function setMaxElWithdrawalRequestFee(uint256 curveId, uint256 fee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to associate max EL withdrawal request fee with|
|`fee`|`uint256`|Max EL withdrawal request fee|


### unsetMaxElWithdrawalRequestFee

Unset max EL withdrawal request fee for the curveId


```solidity
function unsetMaxElWithdrawalRequestFee(uint256 curveId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Curve Id to unset max EL withdrawal request fee for|


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

## Events
### DefaultKeyRemovalChargeSet

```solidity
event DefaultKeyRemovalChargeSet(uint256 value);
```

### DefaultGeneralDelayedPenaltyAdditionalFineSet

```solidity
event DefaultGeneralDelayedPenaltyAdditionalFineSet(uint256 value);
```

### DefaultKeysLimitSet

```solidity
event DefaultKeysLimitSet(uint256 value);
```

### DefaultRewardShareSet

```solidity
event DefaultRewardShareSet(uint256 value);
```

### DefaultPerformanceLeewaySet

```solidity
event DefaultPerformanceLeewaySet(uint256 value);
```

### DefaultStrikesParamsSet

```solidity
event DefaultStrikesParamsSet(uint256 lifetime, uint256 threshold);
```

### DefaultBadPerformancePenaltySet

```solidity
event DefaultBadPerformancePenaltySet(uint256 value);
```

### DefaultPerformanceCoefficientsSet

```solidity
event DefaultPerformanceCoefficientsSet(uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight);
```

### DefaultQueueConfigSet

```solidity
event DefaultQueueConfigSet(uint256 priority, uint256 maxDeposits);
```

### DefaultAllowedExitDelaySet

```solidity
event DefaultAllowedExitDelaySet(uint256 delay);
```

### DefaultExitDelayFeeSet

```solidity
event DefaultExitDelayFeeSet(uint256 penalty);
```

### DefaultMaxElWithdrawalRequestFeeSet

```solidity
event DefaultMaxElWithdrawalRequestFeeSet(uint256 fee);
```

### KeyRemovalChargeSet

```solidity
event KeyRemovalChargeSet(uint256 indexed curveId, uint256 keyRemovalCharge);
```

### GeneralDelayedPenaltyAdditionalFineSet

```solidity
event GeneralDelayedPenaltyAdditionalFineSet(uint256 indexed curveId, uint256 fine);
```

### KeysLimitSet

```solidity
event KeysLimitSet(uint256 indexed curveId, uint256 limit);
```

### QueueConfigSet

```solidity
event QueueConfigSet(uint256 indexed curveId, uint256 priority, uint256 maxDeposits);
```

### RewardShareDataSet

```solidity
event RewardShareDataSet(uint256 indexed curveId, KeyNumberValueInterval[] data);
```

### PerformanceLeewayDataSet

```solidity
event PerformanceLeewayDataSet(uint256 indexed curveId, KeyNumberValueInterval[] data);
```

### StrikesParamsSet

```solidity
event StrikesParamsSet(uint256 indexed curveId, uint256 lifetime, uint256 threshold);
```

### BadPerformancePenaltySet

```solidity
event BadPerformancePenaltySet(uint256 indexed curveId, uint256 penalty);
```

### PerformanceCoefficientsSet

```solidity
event PerformanceCoefficientsSet(
    uint256 indexed curveId, uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight
);
```

### AllowedExitDelaySet

```solidity
event AllowedExitDelaySet(uint256 indexed curveId, uint256 delay);
```

### ExitDelayFeeSet

```solidity
event ExitDelayFeeSet(uint256 indexed curveId, uint256 penalty);
```

### MaxElWithdrawalRequestFeeSet

```solidity
event MaxElWithdrawalRequestFeeSet(uint256 indexed curveId, uint256 fee);
```

### KeyRemovalChargeUnset

```solidity
event KeyRemovalChargeUnset(uint256 indexed curveId);
```

### GeneralDelayedPenaltyAdditionalFineUnset

```solidity
event GeneralDelayedPenaltyAdditionalFineUnset(uint256 indexed curveId);
```

### KeysLimitUnset

```solidity
event KeysLimitUnset(uint256 indexed curveId);
```

### QueueConfigUnset

```solidity
event QueueConfigUnset(uint256 indexed curveId);
```

### RewardShareDataUnset

```solidity
event RewardShareDataUnset(uint256 indexed curveId);
```

### PerformanceLeewayDataUnset

```solidity
event PerformanceLeewayDataUnset(uint256 indexed curveId);
```

### StrikesParamsUnset

```solidity
event StrikesParamsUnset(uint256 indexed curveId);
```

### BadPerformancePenaltyUnset

```solidity
event BadPerformancePenaltyUnset(uint256 indexed curveId);
```

### PerformanceCoefficientsUnset

```solidity
event PerformanceCoefficientsUnset(uint256 indexed curveId);
```

### AllowedExitDelayUnset

```solidity
event AllowedExitDelayUnset(uint256 indexed curveId);
```

### ExitDelayFeeUnset

```solidity
event ExitDelayFeeUnset(uint256 indexed curveId);
```

### MaxElWithdrawalRequestFeeUnset

```solidity
event MaxElWithdrawalRequestFeeUnset(uint256 indexed curveId);
```

## Errors
### InvalidRewardShareData

```solidity
error InvalidRewardShareData();
```

### InvalidPerformanceLeewayData

```solidity
error InvalidPerformanceLeewayData();
```

### InvalidKeyNumberValueIntervals

```solidity
error InvalidKeyNumberValueIntervals();
```

### InvalidPerformanceCoefficients

```solidity
error InvalidPerformanceCoefficients();
```

### InvalidStrikesParams

```solidity
error InvalidStrikesParams();
```

### ZeroMaxDeposits

```solidity
error ZeroMaxDeposits();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### QueueCannotBeUsed

```solidity
error QueueCannotBeUsed();
```

### InvalidAllowedExitDelay

```solidity
error InvalidAllowedExitDelay();
```

## Structs
### MarkedUint248

```solidity
struct MarkedUint248 {
    uint248 value;
    bool isValue;
}
```

### QueueConfig

```solidity
struct QueueConfig {
    uint32 priority;
    uint32 maxDeposits;
}
```

### StrikesParams

```solidity
struct StrikesParams {
    uint32 lifetime;
    uint32 threshold;
}
```

### PerformanceCoefficients

```solidity
struct PerformanceCoefficients {
    uint32 attestationsWeight;
    uint32 blocksWeight;
    uint32 syncWeight;
}
```

### KeyNumberValueInterval
Defines a value interval starting from `minKeyNumber`.
All keys with number >= `minKeyNumber` are assigned the corresponding `value`
until the next interval begins. Intervals must be sorted by ascending `minKeyNumber`
and must start from one (i.e., the first interval must have minKeyNumber == 1).
Example: [{1, 10000}, {11, 8000}] means first 10 keys with 10000, other keys with 8000.


```solidity
struct KeyNumberValueInterval {
    uint256 minKeyNumber;
    uint256 value;
}
```

### InitializationData

```solidity
struct InitializationData {
    uint256 defaultKeyRemovalCharge;
    uint256 defaultGeneralDelayedPenaltyAdditionalFine;
    uint256 defaultKeysLimit;
    uint256 defaultRewardShare;
    uint256 defaultPerformanceLeeway;
    uint256 defaultStrikesLifetime;
    uint256 defaultStrikesThreshold;
    uint256 defaultQueuePriority;
    uint256 defaultQueueMaxDeposits;
    uint256 defaultBadPerformancePenalty;
    uint256 defaultAttestationsWeight;
    uint256 defaultBlocksWeight;
    uint256 defaultSyncWeight;
    uint256 defaultAllowedExitDelay;
    uint256 defaultExitDelayFee;
    uint256 defaultMaxElWithdrawalRequestFee;
}
```

### CurveParameters

```solidity
struct CurveParameters {
    uint256 keyRemovalCharge;
    uint256 generalDelayedPenaltyAdditionalFine;
    uint256 keysLimit;
    uint32 queuePriority;
    uint32 queueMaxDeposits;
    KeyNumberValueInterval[] rewardShareData;
    KeyNumberValueInterval[] performanceLeewayData;
    uint256 strikesLifetime;
    uint256 strikesThreshold;
    uint256 badPerformancePenalty;
    uint256 attestationsWeight;
    uint256 blocksWeight;
    uint256 syncWeight;
    uint256 allowedExitDelay;
    uint256 exitDelayFee;
    uint256 maxElWithdrawalRequestFee;
}
```

