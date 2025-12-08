// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IParametersRegistry {
    struct MarkedUint248 {
        uint248 value;
        bool isValue;
    }

    struct QueueConfig {
        uint32 priority;
        uint32 maxDeposits;
    }

    struct StrikesParams {
        uint32 lifetime;
        uint32 threshold;
    }

    struct PerformanceCoefficients {
        uint32 attestationsWeight;
        uint32 blocksWeight;
        uint32 syncWeight;
    }

    /// @dev Defines a value interval starting from `minKeyNumber`.
    ///      All keys with number >= `minKeyNumber` are assigned the corresponding `value`
    ///      until the next interval begins. Intervals must be sorted by ascending `minKeyNumber`
    ///      and must start from one (i.e., the first interval must have minKeyNumber == 1).
    ///      Example: [{1, 10000}, {11, 8000}] means first 10 keys with 10000, other keys with 8000.
    struct KeyNumberValueInterval {
        uint256 minKeyNumber;
        uint256 value;
    }

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
        uint256 defaultMaxWithdrawalRequestFee;
    }

    event DefaultKeyRemovalChargeSet(uint256 value);
    event DefaultGeneralDelayedPenaltyAdditionalFineSet(uint256 value);
    event DefaultKeysLimitSet(uint256 value);
    event DefaultRewardShareSet(uint256 value);
    event DefaultPerformanceLeewaySet(uint256 value);
    event DefaultStrikesParamsSet(uint256 lifetime, uint256 threshold);
    event DefaultBadPerformancePenaltySet(uint256 value);
    event DefaultPerformanceCoefficientsSet(
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    );
    event DefaultQueueConfigSet(uint256 priority, uint256 maxDeposits);
    event DefaultAllowedExitDelaySet(uint256 delay);
    event DefaultExitDelayFeeSet(uint256 penalty);
    event DefaultMaxWithdrawalRequestFeeSet(uint256 fee);

    event KeyRemovalChargeSet(
        uint256 indexed curveId,
        uint256 keyRemovalCharge
    );
    event GeneralDelayedPenaltyAdditionalFineSet(
        uint256 indexed curveId,
        uint256 fine
    );
    event KeysLimitSet(uint256 indexed curveId, uint256 limit);
    event QueueConfigSet(
        uint256 indexed curveId,
        uint256 priority,
        uint256 maxDeposits
    );
    event RewardShareDataSet(
        uint256 indexed curveId,
        KeyNumberValueInterval[] data
    );
    event PerformanceLeewayDataSet(
        uint256 indexed curveId,
        KeyNumberValueInterval[] data
    );
    event StrikesParamsSet(
        uint256 indexed curveId,
        uint256 lifetime,
        uint256 threshold
    );
    event BadPerformancePenaltySet(uint256 indexed curveId, uint256 penalty);
    event PerformanceCoefficientsSet(
        uint256 indexed curveId,
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    );
    event AllowedExitDelaySet(uint256 indexed curveId, uint256 delay);
    event ExitDelayFeeSet(uint256 indexed curveId, uint256 penalty);
    event MaxWithdrawalRequestFeeSet(uint256 indexed curveId, uint256 fee);

    event KeyRemovalChargeUnset(uint256 indexed curveId);
    event GeneralDelayedPenaltyAdditionalFineUnset(uint256 indexed curveId);
    event KeysLimitUnset(uint256 indexed curveId);
    event QueueConfigUnset(uint256 indexed curveId);
    event RewardShareDataUnset(uint256 indexed curveId);
    event PerformanceLeewayDataUnset(uint256 indexed curveId);
    event StrikesParamsUnset(uint256 indexed curveId);
    event BadPerformancePenaltyUnset(uint256 indexed curveId);
    event PerformanceCoefficientsUnset(uint256 indexed curveId);
    event AllowedExitDelayUnset(uint256 indexed curveId);
    event ExitDelayFeeUnset(uint256 indexed curveId);
    event MaxWithdrawalRequestFeeUnset(uint256 indexed curveId);

    error InvalidRewardShareData();
    error InvalidPerformanceLeewayData();
    error InvalidKeyNumberValueIntervals();
    error InvalidPerformanceCoefficients();
    error InvalidStrikesParams();
    error ZeroMaxDeposits();
    error ZeroAdminAddress();
    error QueueCannotBeUsed();
    error InvalidAllowedExitDelay();
    error ZeroQueueLowestPriority();

    /// @notice Role to manage general penalties and charges parameters: key removal charge and general delayed penalty additional fine
    function MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE()
        external
        view
        returns (bytes32);

    /// @notice Role to manage keys limit parameter
    function MANAGE_KEYS_LIMIT_ROLE() external view returns (bytes32);

    /// @notice Role to manage queue config
    function MANAGE_QUEUE_CONFIG_ROLE() external view returns (bytes32);

    /// @notice Role to manage performance parameters: performance leeway, strikes params, bad performance penalty, performance coefficients
    function MANAGE_PERFORMANCE_PARAMETERS_ROLE()
        external
        view
        returns (bytes32);

    /// @notice Role to manage reward share parameters
    function MANAGE_REWARD_SHARE_ROLE() external view returns (bytes32);

    /// @notice Role to manage validator exit related parameters: allowed exit delay, exit delay fee, max withdrawal request fee
    function MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE()
        external
        view
        returns (bytes32);

    /// @notice The lowest priority a deposit queue can be assigned with. This constant is not used in Curated Module
    function QUEUE_LOWEST_PRIORITY() external view returns (uint256);

    /// @notice Get default value for the key removal charge. This parameter is not used in Curated Module
    function defaultKeyRemovalCharge() external returns (uint256);

    /// @notice Get default value for the general delayed penalty additional fine
    function defaultGeneralDelayedPenaltyAdditionalFine()
        external
        returns (uint256);

    /// @notice Get default value for the keys limit
    function defaultKeysLimit() external returns (uint256);

    /// @notice Get default value for QueueConfig. This parameter is not used in Curated Module
    /// @return priority Default queue priority
    /// @return maxDeposits Default maximum number of the first deposits a Node Operator can get via the priority queue
    function defaultQueueConfig()
        external
        returns (uint32 priority, uint32 maxDeposits);

    /// @notice Get default value for the reward share
    function defaultRewardShare() external returns (uint256);

    /// @notice Get default value for the performance leeway
    function defaultPerformanceLeeway() external returns (uint256);

    /// @notice Get default value for the strikes lifetime (frames count) and threshold (integer)
    /// @return lifetime The default number of Performance Oracle frames to store strikes values
    /// @return threshold The default strikes value leading to validator force ejection.
    function defaultStrikesParams()
        external
        returns (uint32 lifetime, uint32 threshold);

    /// @notice Get default value for the bad performance penalty
    function defaultBadPerformancePenalty() external returns (uint256);

    /// @notice Get default value for the performance coefficients
    /// @return attestationsWeight Attestations effectiveness weight
    /// @return blocksWeight Block proposals effectiveness weight
    /// @return syncWeight Sync participation effectiveness weight
    function defaultPerformanceCoefficients()
        external
        returns (
            uint32 attestationsWeight,
            uint32 blocksWeight,
            uint32 syncWeight
        );

    /// @notice Get default value for the allowed exit delay
    function defaultAllowedExitDelay() external returns (uint256);

    /// @notice Get default value for exit delay penalty
    function defaultExitDelayFee() external returns (uint256);

    /// @notice Get default value for max withdrawal request fee
    function defaultMaxWithdrawalRequestFee() external returns (uint256);

    /// @notice Set default value for the key removal charge. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module
    /// @param keyRemovalCharge value to be set as default for the key removal charge
    function setDefaultKeyRemovalCharge(uint256 keyRemovalCharge) external;

    /// @notice Set default value for the general delayed penalty additional fine. Default value is used if a specific value is not set for the curveId
    /// @param fine value to be set as default for the general delayed penalty additional fine
    function setDefaultGeneralDelayedPenaltyAdditionalFine(
        uint256 fine
    ) external;

    /// @notice Set default value for the keys limit. Default value is used if a specific value is not set for the curveId
    /// @param limit value to be set as default for the keys limit
    function setDefaultKeysLimit(uint256 limit) external;

    /// @notice Set default value for QueueConfig. Default value is used if a specific value is not set for the curveId. This parameter is not used in Curated Module
    /// @param priority Queue priority.
    /// @param maxDeposits Maximum number of the first deposits a Node Operator can get via the priority queue.
    ///                    Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue
    ///                    until the Node Operator has totalDepositedKeys + enqueued >= 10.
    function setDefaultQueueConfig(
        uint256 priority,
        uint256 maxDeposits
    ) external;

    /// @notice Set default value for the reward share. Default value is used if a specific value is not set for the curveId
    /// @param share value to be set as default for the reward share
    function setDefaultRewardShare(uint256 share) external;

    /// @notice Set default value for the performance leeway. Default value is used if a specific value is not set for the curveId
    /// @param leeway value to be set as default for the performance leeway
    function setDefaultPerformanceLeeway(uint256 leeway) external;

    /// @notice Set default values for the strikes lifetime and threshold. Default values are used if specific values are not set for the curveId
    /// @param lifetime The default number of Performance Oracle frames to store strikes values
    /// @param threshold The default strikes value leading to validator force ejection.
    function setDefaultStrikesParams(
        uint256 lifetime,
        uint256 threshold
    ) external;

    /// @notice Set the default value for the bad performance penalty for a single 32 ether validator
    /// This value is used if a specific value is not set for the curveId
    /// @param penalty value to be set as default for the bad performance penalty
    function setDefaultBadPerformancePenalty(uint256 penalty) external;

    /// @notice Set default values for the performance coefficients. Default values are used if specific values are not set for the curveId
    /// @param attestationsWeight value to be set as default for the attestations effectiveness weight
    /// @param blocksWeight value to be set as default for block proposals effectiveness weight
    /// @param syncWeight value to be set as default for sync participation effectiveness weight
    function setDefaultPerformanceCoefficients(
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) external;

    /// @notice set default value for allowed delay before the exit was initiated exit delay in seconds. Default value is used if a specific value is not set for the curveId
    /// @param delay value to be set as default for the allowed exit delay
    function setDefaultAllowedExitDelay(uint256 delay) external;

    /// @notice Set the default value for exit delay penalty for a single 32 ether validator
    /// This value is used if a specific value is not set for the curveId
    /// @param fee The value to be set as default for the exit delay fee
    function setDefaultExitDelayFee(uint256 fee) external;

    /// @notice set default value for max withdrawal request fee. Default value is used if a specific value is not set for the curveId
    /// @param fee value to be set as default for the max withdrawal request fee
    function setDefaultMaxWithdrawalRequestFee(uint256 fee) external;

    /// @notice Set key removal charge for the curveId. This parameter is not used in Curated Module
    /// @param curveId Curve Id to associate key removal charge with
    /// @param keyRemovalCharge Key removal charge
    function setKeyRemovalCharge(
        uint256 curveId,
        uint256 keyRemovalCharge
    ) external;

    /// @notice Unset key removal charge for the curveId. This parameter is not used in Curated Module
    /// @param curveId Curve Id to unset custom key removal charge for
    function unsetKeyRemovalCharge(uint256 curveId) external;

    /// @notice Get key removal charge by the curveId. A charge is taken from the bond for each removed key from the module. This parameter is not used in Curated Module
    /// @dev `defaultKeyRemovalCharge` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get key removal charge for
    /// @return keyRemovalCharge Key removal charge
    function getKeyRemovalCharge(
        uint256 curveId
    ) external view returns (uint256 keyRemovalCharge);

    /// @notice Set general delayed penalty additional fine for the curveId.
    /// @param curveId Curve Id to associate general delayed penalty additional fine limit with
    /// @param fine General delayed penalty additional fine
    function setGeneralDelayedPenaltyAdditionalFine(
        uint256 curveId,
        uint256 fine
    ) external;

    /// @notice Unset general delayed penalty additional fine for the curveId
    /// @param curveId Curve Id to unset custom general delayed penalty additional fine for
    function unsetGeneralDelayedPenaltyAdditionalFine(uint256 curveId) external;

    /// @notice Get general delayed penalty additional fine by the curveId. Additional fine is added to the general delayed penalty by CSM
    /// @dev `defaultGeneralDelayedPenaltyAdditionalFine` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get general delayed penalty additional fine for
    /// @return fine General delayed penalty additional fine
    function getGeneralDelayedPenaltyAdditionalFine(
        uint256 curveId
    ) external view returns (uint256 fine);

    /// @notice Set keys limit for the curveId.
    /// @param curveId Curve Id to associate keys limit with
    /// @param limit Keys limit
    function setKeysLimit(uint256 curveId, uint256 limit) external;

    /// @notice Unset key removal charge for the curveId
    /// @param curveId Curve Id to unset custom key removal charge for
    function unsetKeysLimit(uint256 curveId) external;

    /// @notice Get keys limit by the curveId. A limit indicates the maximal amount of the non-exited keys Node Operator can upload
    /// @dev `defaultKeysLimit` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get keys limit for
    /// @return limit Keys limit
    function getKeysLimit(
        uint256 curveId
    ) external view returns (uint256 limit);

    /// @notice Sets the provided config to the given curve. This parameter is not used in Curated Module
    /// @param curveId Curve Id to set the config.
    /// @param priority Queue priority.
    /// @param maxDeposits Maximum number of the first deposits a Node Operator can get via the priority queue.
    ///                    Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue
    ///                    until the Node Operator has totalDepositedKeys + enqueued >= 10.
    function setQueueConfig(
        uint256 curveId,
        uint256 priority,
        uint256 maxDeposits
    ) external;

    /// @notice Set the given curve's config to the default one. This parameter is not used in Curated Module
    /// @param curveId Curve Id to unset custom config.
    function unsetQueueConfig(uint256 curveId) external;

    /// @notice Get the queue config for the given curve. This parameter is not used in Curated Module
    /// @param curveId Curve Id to get the queue config for.
    /// @return priority Queue priority.
    /// @param maxDeposits Maximum number of the first deposits a Node Operator can get via the priority queue.
    ///                    Ex. with `maxDeposits = 10` the Node Operator сan get keys added to the priority queue
    ///                    until the Node Operator has totalDepositedKeys + enqueued >= 10.
    function getQueueConfig(
        uint256 curveId
    ) external view returns (uint32 priority, uint32 maxDeposits);

    /// @notice Set reward share parameters for the curveId
    /// @dev KeyNumberValueInterval = [[1, 10000], [11, 8000], [51, 5000]] stands for
    ///      100% rewards for the first 10 keys, 80% rewards for the keys 11-50, and 50% rewards for the keys > 50
    /// @param curveId Curve Id to associate reward share data with
    /// @param data Interval values for keys count and reward share percentages in BP (ex. [[1, 10000], [11, 8000], [51, 5000]])
    function setRewardShareData(
        uint256 curveId,
        KeyNumberValueInterval[] calldata data
    ) external;

    /// @notice Unset reward share parameters for the curveId
    /// @param curveId Curve Id to unset custom reward share parameters for
    function unsetRewardShareData(uint256 curveId) external;

    /// @notice Get reward share parameters by the curveId.
    /// @dev Returns [[1, defaultRewardShare]] if no intervals are set for the given curveId.
    /// @dev KeyNumberValueInterval = [[1, 10000], [11, 8000], [51, 5000]] stands for
    ///      100% rewards for the first 10 keys, 80% rewards for the keys 11-50, and 50% rewards for the keys > 50
    /// @param curveId Curve Id to get reward share data for
    /// @param data Interval values for keys count and reward share percentages in BP (ex. [[1, 10000], [11, 8000], [51, 5000]])
    function getRewardShareData(
        uint256 curveId
    ) external view returns (KeyNumberValueInterval[] memory data);

    /// @notice Set performance leeway parameters for the curveId
    /// @dev Returns [[1, defaultPerformanceLeeway]] if no intervals are set for the given curveId.
    /// @dev KeyNumberValueInterval = [[1, 500], [101, 450], [501, 400]] stands for
    ///      5% performance leeway for the first 100 keys, 4.5% performance leeway for the keys 101-500, and 4% performance leeway for the keys > 500
    /// @param curveId Curve Id to associate performance leeway data with
    /// @param data Interval values for keys count and performance leeway percentages in BP (ex. [[1, 500], [101, 450], [501, 400]])
    function setPerformanceLeewayData(
        uint256 curveId,
        KeyNumberValueInterval[] calldata data
    ) external;

    /// @notice Unset performance leeway parameters for the curveId
    /// @param curveId Curve Id to unset custom performance leeway parameters for
    function unsetPerformanceLeewayData(uint256 curveId) external;

    /// @notice Get performance leeway parameters by the curveId
    /// @dev Returns [[1, defaultPerformanceLeeway]] if no intervals are set for the given curveId.
    /// @dev KeyNumberValueInterval = [[1, 500], [101, 450], [501, 400]] stands for
    ///      5% performance leeway for the first 100 keys, 4.5% performance leeway for the keys 101-500, and 4% performance leeway for the keys > 500
    /// @param curveId Curve Id to get performance leeway data for
    /// @param data Interval values for keys count and performance leeway percentages in BP (ex. [[1, 500], [101, 450], [501, 400]])
    function getPerformanceLeewayData(
        uint256 curveId
    ) external view returns (KeyNumberValueInterval[] memory data);

    /// @notice Set performance strikes lifetime and threshold for the curveId
    /// @param curveId Curve Id to associate performance strikes lifetime and threshold with
    /// @param lifetime Number of Performance Oracle frames to store strikes values
    /// @param threshold The strikes value leading to validator force ejection
    function setStrikesParams(
        uint256 curveId,
        uint256 lifetime,
        uint256 threshold
    ) external;

    /// @notice Unset custom performance strikes lifetime and threshold for the curveId
    /// @param curveId Curve Id to unset custom performance strikes lifetime and threshold for
    function unsetStrikesParams(uint256 curveId) external;

    /// @notice Get performance strikes lifetime and threshold by the curveId
    /// @dev `defaultStrikesParams` are returned if the value is not set for the given curveId
    /// @param curveId Curve Id to get performance strikes lifetime and threshold for
    /// @return lifetime Number of Performance Oracle frames to store strikes values
    /// @return threshold The strikes value leading to validator force ejection
    function getStrikesParams(
        uint256 curveId
    ) external view returns (uint256 lifetime, uint256 threshold);

    /// @notice Set the bad performance penalty for the curveId for a single 32 ether validator
    /// @param curveId Curve Id to associate bad performance penalty with
    /// @param penalty Bad performance penalty
    function setBadPerformancePenalty(
        uint256 curveId,
        uint256 penalty
    ) external;

    /// @notice Unset bad performance penalty for the curveId
    /// @param curveId Curve Id to unset custom bad performance penalty for
    function unsetBadPerformancePenalty(uint256 curveId) external;

    /// @notice Get bad performance penalty for a single 32 ether validator by the curveId
    /// @dev `defaultBadPerformancePenalty` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get bad performance penalty for
    /// @return penalty Bad performance penalty
    function getBadPerformancePenalty(
        uint256 curveId
    ) external view returns (uint256 penalty);

    /// @notice Set performance coefficients for the curveId
    /// @param curveId Curve Id to associate performance coefficients with
    /// @param attestationsWeight Attestations effectiveness weight
    /// @param blocksWeight Block proposals effectiveness weight
    /// @param syncWeight Sync participation effectiveness weight
    function setPerformanceCoefficients(
        uint256 curveId,
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) external;

    /// @notice Unset custom performance coefficients for the curveId
    /// @param curveId Curve Id to unset custom performance coefficients for
    function unsetPerformanceCoefficients(uint256 curveId) external;

    /// @notice Get performance coefficients by the curveId
    /// @dev `defaultPerformanceCoefficients` are returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get performance coefficients for
    /// @return attestationsWeight Attestations effectiveness weight
    /// @return blocksWeight Block proposals effectiveness weight
    /// @return syncWeight Sync participation effectiveness weight
    function getPerformanceCoefficients(
        uint256 curveId
    )
        external
        view
        returns (
            uint256 attestationsWeight,
            uint256 blocksWeight,
            uint256 syncWeight
        );

    /// @notice Set allowed exit delay for the curveId in seconds
    /// @param curveId Curve Id to associate allowed exit delay with
    /// @param delay allowed exit delay
    function setAllowedExitDelay(uint256 curveId, uint256 delay) external;

    /// @notice Unset exit timeframe deadline delay for the curveId
    /// @param curveId Curve Id to unset allowed exit delay for
    function unsetAllowedExitDelay(uint256 curveId) external;

    /// @notice Get allowed exit delay by the curveId in seconds
    /// @dev `defaultAllowedExitDelay` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get allowed exit delay for
    function getAllowedExitDelay(
        uint256 curveId
    ) external view returns (uint256 delay);

    /// @notice Set the exit delay penalty for a single 32 ether validator for the given curveId
    /// @dev cannot be zero
    /// @param curveId Curve Id to associate exit delay penalty with
    /// @param fee Exit delay fee
    function setExitDelayFee(uint256 curveId, uint256 fee) external;

    /// @notice Unset exit delay penalty for the curveId
    /// @param curveId The curve ID for unsetting the exit delay fee
    function unsetExitDelayFee(uint256 curveId) external;

    /// @notice Get exit delay penalty for a single 32 ether validator by the curveId
    /// @dev `defaultExitDelayFee` is returned if the value is not set for the given curveId.
    /// @param curveId Curve ID to get the exit delay fee for
    function getExitDelayFee(
        uint256 curveId
    ) external view returns (uint256 penalty);

    /// @notice Set max withdrawal request fee for the curveId
    /// @param curveId Curve Id to associate max withdrawal request fee with
    /// @param fee max withdrawal request fee
    function setMaxWithdrawalRequestFee(uint256 curveId, uint256 fee) external;

    /// @notice Unset max withdrawal request fee for the curveId
    /// @param curveId Curve Id to unset max withdrawal request fee for
    function unsetMaxWithdrawalRequestFee(uint256 curveId) external;

    /// @notice Get max withdrawal request fee by the curveId
    /// @dev `defaultMaxWithdrawalRequestFee` is returned if the value is not set for the given curveId.
    /// @param curveId Curve Id to get max withdrawal request fee for
    function getMaxWithdrawalRequestFee(
        uint256 curveId
    ) external view returns (uint256 fee);

    /// @notice Returns the initialized version of the contract
    function getInitializedVersion() external view returns (uint64);
}
