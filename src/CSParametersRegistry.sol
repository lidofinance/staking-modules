// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ICSParametersRegistry } from "./interfaces/ICSParametersRegistry.sol";

/// @dev There are no upper limit checks except for the basis points (BP) values
///      since with the introduction of Dual Governance any malicious changes to the parameters can be objected by stETH holders.
// solhint-disable-next-line max-states-count
contract CSParametersRegistry is
    ICSParametersRegistry,
    Initializable,
    AccessControlEnumerableUpgradeable
{
    using SafeCast for uint256;

    bytes32 public constant MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE =
        keccak256("MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE");
    bytes32 public constant MANAGE_KEYS_LIMIT_ROLE =
        keccak256("MANAGE_KEYS_LIMIT_ROLE");
    bytes32 public constant MANAGE_QUEUE_CONFIG_ROLE =
        keccak256("MANAGE_QUEUE_CONFIG_ROLE");
    bytes32 public constant MANAGE_PERFORMANCE_PARAMETERS_ROLE =
        keccak256("MANAGE_PERFORMANCE_PARAMETERS_ROLE");
    bytes32 public constant MANAGE_REWARD_SHARE_ROLE =
        keccak256("MANAGE_REWARD_SHARE_ROLE");
    bytes32 public constant MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE =
        keccak256("MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE");

    /// @dev Maximal value for basis points (BP)
    ///      1 BP = 0.01%
    uint256 internal constant MAX_BP = 10000;

    /// @dev QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].
    ///      Unused in CuratedModule.sol
    uint256 public immutable QUEUE_LOWEST_PRIORITY;

    ////////////////////////////////////////////////////////////////////////////////
    // State variables below
    ////////////////////////////////////////////////////////////////////////////////

    /// @dev Key removal charge is not used in Curated Module
    uint256 public defaultKeyRemovalCharge;
    mapping(uint256 curveId => MarkedUint248) internal _keyRemovalCharges;

    uint256 public defaultGeneralDelayedPenaltyAdditionalFine;
    mapping(uint256 curveId => MarkedUint248)
        internal _generalDelayedPenaltyAdditionalFines;

    uint256 public defaultKeysLimit;
    mapping(uint256 curveId => MarkedUint248) internal _keysLimits;

    /// @dev Queue config is not used in Curated Module
    QueueConfig public defaultQueueConfig;
    mapping(uint256 curveId => QueueConfig) internal _queueConfigs;

    /// @dev Default value for the reward share. Can be only be set as a flat value due to possible sybil attacks
    ///      Decreased reward share for some validators > N will promote sybils. Increased reward share for validators > N will give large operators an advantage
    uint256 public defaultRewardShare;
    mapping(uint256 curveId => KeyNumberValueInterval[])
        internal _rewardShareData;

    /// @dev Default value for the performance leeway. Can be only be set as a flat value due to possible sybil attacks
    ///      Decreased performance leeway for some validators > N will promote sybils. Increased performance leeway for validators > N will give large operators an advantage
    uint256 public defaultPerformanceLeeway;
    mapping(uint256 curveId => KeyNumberValueInterval[])
        internal _performanceLeewayData;

    StrikesParams public defaultStrikesParams;
    mapping(uint256 curveId => StrikesParams) internal _strikesParams;

    uint256 public defaultBadPerformancePenalty;
    mapping(uint256 curveId => MarkedUint248) internal _badPerformancePenalties;

    PerformanceCoefficients public defaultPerformanceCoefficients;
    mapping(uint256 curveId => PerformanceCoefficients)
        internal _performanceCoefficients;

    uint256 public defaultAllowedExitDelay;
    mapping(uint256 => uint256) internal _allowedExitDelay;

    uint256 public defaultExitDelayFee;
    mapping(uint256 => MarkedUint248) internal _exitDelayFees;

    uint256 public defaultMaxWithdrawalRequestFee;
    mapping(uint256 => MarkedUint248) internal _maxWithdrawalRequestFees;

    modifier onlyRoleMemberOrAdmin(bytes32 role) {
        address sender = msg.sender;
        if (!(hasRole(role, sender) || hasRole(getRoleAdmin(role), sender))) {
            revert AccessControlUnauthorizedAccount(sender, role);
        }
        _;
    }

    constructor(uint256 queueLowestPriority) {
        if (queueLowestPriority == 0) {
            revert ZeroQueueLowestPriority();
        }

        QUEUE_LOWEST_PRIORITY = queueLowestPriority;

        _disableInitializers();
    }

    /// @notice initialize contract
    function initialize(
        address admin,
        InitializationData calldata data
    ) external initializer {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        _setDefaultKeyRemovalCharge(data.defaultKeyRemovalCharge);
        _setDefaultGeneralDelayedPenaltyAdditionalFine(
            data.defaultGeneralDelayedPenaltyAdditionalFine
        );
        _setDefaultKeysLimit(data.defaultKeysLimit);
        _setDefaultRewardShare(data.defaultRewardShare);
        _setDefaultPerformanceLeeway(data.defaultPerformanceLeeway);
        _setDefaultStrikesParams(
            data.defaultStrikesLifetime,
            data.defaultStrikesThreshold
        );
        _setDefaultBadPerformancePenalty(data.defaultBadPerformancePenalty);
        _setDefaultPerformanceCoefficients(
            data.defaultAttestationsWeight,
            data.defaultBlocksWeight,
            data.defaultSyncWeight
        );
        _setDefaultQueueConfig(
            data.defaultQueuePriority,
            data.defaultQueueMaxDeposits
        );
        _setDefaultAllowedExitDelay(data.defaultAllowedExitDelay);
        _setDefaultExitDelayFee(data.defaultExitDelayFee);
        _setDefaultMaxWithdrawalRequestFee(data.defaultMaxWithdrawalRequestFee);

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Setters for default parameters
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICSParametersRegistry
    function setDefaultKeyRemovalCharge(
        uint256 keyRemovalCharge
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        _setDefaultKeyRemovalCharge(keyRemovalCharge);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultGeneralDelayedPenaltyAdditionalFine(
        uint256 fine
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        _setDefaultGeneralDelayedPenaltyAdditionalFine(fine);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultKeysLimit(
        uint256 limit
    ) external onlyRoleMemberOrAdmin(MANAGE_KEYS_LIMIT_ROLE) {
        _setDefaultKeysLimit(limit);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultQueueConfig(
        uint256 priority,
        uint256 maxDeposits
    ) external onlyRoleMemberOrAdmin(MANAGE_QUEUE_CONFIG_ROLE) {
        _setDefaultQueueConfig(priority, maxDeposits);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultRewardShare(
        uint256 share
    ) external onlyRoleMemberOrAdmin(MANAGE_REWARD_SHARE_ROLE) {
        _setDefaultRewardShare(share);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultPerformanceLeeway(
        uint256 leeway
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _setDefaultPerformanceLeeway(leeway);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultStrikesParams(
        uint256 lifetime,
        uint256 threshold
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _setDefaultStrikesParams(lifetime, threshold);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultBadPerformancePenalty(
        uint256 penalty
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _setDefaultBadPerformancePenalty(penalty);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultPerformanceCoefficients(
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _setDefaultPerformanceCoefficients(
            attestationsWeight,
            blocksWeight,
            syncWeight
        );
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultAllowedExitDelay(
        uint256 delay
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _setDefaultAllowedExitDelay(delay);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultExitDelayFee(
        uint256 penalty
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _setDefaultExitDelayFee(penalty);
    }

    /// @inheritdoc ICSParametersRegistry
    function setDefaultMaxWithdrawalRequestFee(
        uint256 fee
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _setDefaultMaxWithdrawalRequestFee(fee);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Setters for per-curve parameters
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICSParametersRegistry
    function setKeyRemovalCharge(
        uint256 curveId,
        uint256 keyRemovalCharge
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        _keyRemovalCharges[curveId] = MarkedUint248(
            keyRemovalCharge.toUint248(),
            true
        );
        emit KeyRemovalChargeSet(curveId, keyRemovalCharge);
    }

    /// @inheritdoc ICSParametersRegistry
    function setGeneralDelayedPenaltyAdditionalFine(
        uint256 curveId,
        uint256 fine
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        _generalDelayedPenaltyAdditionalFines[curveId] = MarkedUint248(
            fine.toUint248(),
            true
        );
        emit GeneralDelayedPenaltyAdditionalFineSet(curveId, fine);
    }

    /// @inheritdoc ICSParametersRegistry
    function setKeysLimit(
        uint256 curveId,
        uint256 limit
    ) external onlyRoleMemberOrAdmin(MANAGE_KEYS_LIMIT_ROLE) {
        _keysLimits[curveId] = MarkedUint248(limit.toUint248(), true);
        emit KeysLimitSet(curveId, limit);
    }

    /// @inheritdoc ICSParametersRegistry
    function setQueueConfig(
        uint256 curveId,
        uint256 priority,
        uint256 maxDeposits
    ) external onlyRoleMemberOrAdmin(MANAGE_QUEUE_CONFIG_ROLE) {
        _validateQueueConfig(priority, maxDeposits);
        _queueConfigs[curveId] = QueueConfig({
            priority: priority.toUint32(),
            maxDeposits: maxDeposits.toUint32()
        });
        emit QueueConfigSet(curveId, priority, maxDeposits);
    }

    /// @inheritdoc ICSParametersRegistry
    function setRewardShareData(
        uint256 curveId,
        KeyNumberValueInterval[] calldata data
    ) external onlyRoleMemberOrAdmin(MANAGE_REWARD_SHARE_ROLE) {
        _validateKeyNumberValueIntervals(data);
        KeyNumberValueInterval[] storage intervals = _rewardShareData[curveId];
        if (intervals.length > 0) {
            delete _rewardShareData[curveId];
        }
        for (uint256 i = 0; i < data.length; ++i) {
            intervals.push(data[i]);
        }
        emit RewardShareDataSet(curveId, data);
    }

    /// @inheritdoc ICSParametersRegistry
    function setPerformanceLeewayData(
        uint256 curveId,
        KeyNumberValueInterval[] calldata data
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _validateKeyNumberValueIntervals(data);
        KeyNumberValueInterval[] storage intervals = _performanceLeewayData[
            curveId
        ];
        if (intervals.length > 0) {
            delete _performanceLeewayData[curveId];
        }
        for (uint256 i = 0; i < data.length; ++i) {
            intervals.push(data[i]);
        }
        emit PerformanceLeewayDataSet(curveId, data);
    }

    /// @inheritdoc ICSParametersRegistry
    function setStrikesParams(
        uint256 curveId,
        uint256 lifetime,
        uint256 threshold
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _validateStrikesParams(lifetime, threshold);
        _strikesParams[curveId] = StrikesParams(
            lifetime.toUint32(),
            threshold.toUint32()
        );
        emit StrikesParamsSet(curveId, lifetime, threshold);
    }

    /// @inheritdoc ICSParametersRegistry
    function setBadPerformancePenalty(
        uint256 curveId,
        uint256 penalty
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _badPerformancePenalties[curveId] = MarkedUint248(
            penalty.toUint248(),
            true
        );
        emit BadPerformancePenaltySet(curveId, penalty);
    }

    /// @inheritdoc ICSParametersRegistry
    function setPerformanceCoefficients(
        uint256 curveId,
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        _validatePerformanceCoefficients(
            attestationsWeight,
            blocksWeight,
            syncWeight
        );
        _performanceCoefficients[curveId] = PerformanceCoefficients(
            attestationsWeight.toUint32(),
            blocksWeight.toUint32(),
            syncWeight.toUint32()
        );
        emit PerformanceCoefficientsSet(
            curveId,
            attestationsWeight,
            blocksWeight,
            syncWeight
        );
    }

    /// @inheritdoc ICSParametersRegistry
    function setAllowedExitDelay(
        uint256 curveId,
        uint256 delay
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _validateAllowedExitDelay(delay);
        _allowedExitDelay[curveId] = delay;
        emit AllowedExitDelaySet(curveId, delay);
    }

    /// @inheritdoc ICSParametersRegistry
    function setExitDelayFee(
        uint256 curveId,
        uint256 penalty
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _exitDelayFees[curveId] = MarkedUint248(penalty.toUint248(), true);
        emit ExitDelayFeeSet(curveId, penalty);
    }

    /// @inheritdoc ICSParametersRegistry
    function setMaxWithdrawalRequestFee(
        uint256 curveId,
        uint256 fee
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        _maxWithdrawalRequestFees[curveId] = MarkedUint248(
            fee.toUint248(),
            true
        );
        emit MaxWithdrawalRequestFeeSet(curveId, fee);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Unsetters for per-curve parameters
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICSParametersRegistry
    function unsetKeyRemovalCharge(
        uint256 curveId
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        delete _keyRemovalCharges[curveId];
        emit KeyRemovalChargeUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetGeneralDelayedPenaltyAdditionalFine(
        uint256 curveId
    )
        external
        onlyRoleMemberOrAdmin(MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE)
    {
        delete _generalDelayedPenaltyAdditionalFines[curveId];
        emit GeneralDelayedPenaltyAdditionalFineUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetKeysLimit(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_KEYS_LIMIT_ROLE) {
        delete _keysLimits[curveId];
        emit KeysLimitUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetQueueConfig(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_QUEUE_CONFIG_ROLE) {
        delete _queueConfigs[curveId];
        emit QueueConfigUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetRewardShareData(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_REWARD_SHARE_ROLE) {
        delete _rewardShareData[curveId];
        emit RewardShareDataUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetPerformanceLeewayData(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        delete _performanceLeewayData[curveId];
        emit PerformanceLeewayDataUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetStrikesParams(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        delete _strikesParams[curveId];
        emit StrikesParamsUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetBadPerformancePenalty(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        delete _badPerformancePenalties[curveId];
        emit BadPerformancePenaltyUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetPerformanceCoefficients(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_PERFORMANCE_PARAMETERS_ROLE) {
        delete _performanceCoefficients[curveId];
        emit PerformanceCoefficientsUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetAllowedExitDelay(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        delete _allowedExitDelay[curveId];
        emit AllowedExitDelayUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetExitDelayFee(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        delete _exitDelayFees[curveId];
        emit ExitDelayFeeUnset(curveId);
    }

    /// @inheritdoc ICSParametersRegistry
    function unsetMaxWithdrawalRequestFee(
        uint256 curveId
    ) external onlyRoleMemberOrAdmin(MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE) {
        delete _maxWithdrawalRequestFees[curveId];
        emit MaxWithdrawalRequestFeeUnset(curveId);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Getters for per-curve parameters
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICSParametersRegistry
    function getKeyRemovalCharge(
        uint256 curveId
    ) external view returns (uint256 keyRemovalCharge) {
        MarkedUint248 storage data = _keyRemovalCharges[curveId];
        return data.isValue ? data.value : defaultKeyRemovalCharge;
    }

    /// @inheritdoc ICSParametersRegistry
    function getGeneralDelayedPenaltyAdditionalFine(
        uint256 curveId
    ) external view returns (uint256 fine) {
        MarkedUint248 storage data = _generalDelayedPenaltyAdditionalFines[
            curveId
        ];
        return
            data.isValue
                ? data.value
                : defaultGeneralDelayedPenaltyAdditionalFine;
    }

    /// @inheritdoc ICSParametersRegistry
    function getKeysLimit(
        uint256 curveId
    ) external view returns (uint256 limit) {
        MarkedUint248 storage data = _keysLimits[curveId];
        return data.isValue ? data.value : defaultKeysLimit;
    }

    /// @inheritdoc ICSParametersRegistry
    function getQueueConfig(
        uint256 curveId
    ) external view returns (uint32 queuePriority, uint32 maxDeposits) {
        QueueConfig storage config = _queueConfigs[curveId];

        if (config.maxDeposits == 0) {
            return (
                defaultQueueConfig.priority,
                defaultQueueConfig.maxDeposits
            );
        }

        return (config.priority, config.maxDeposits);
    }

    /// @inheritdoc ICSParametersRegistry
    function getRewardShareData(
        uint256 curveId
    ) external view returns (KeyNumberValueInterval[] memory data) {
        data = _rewardShareData[curveId];
        if (data.length == 0) {
            data = new KeyNumberValueInterval[](1);
            data[0] = KeyNumberValueInterval(1, defaultRewardShare);
        }
    }

    /// @inheritdoc ICSParametersRegistry
    function getPerformanceLeewayData(
        uint256 curveId
    ) external view returns (KeyNumberValueInterval[] memory data) {
        data = _performanceLeewayData[curveId];
        if (data.length == 0) {
            data = new KeyNumberValueInterval[](1);
            data[0] = KeyNumberValueInterval(1, defaultPerformanceLeeway);
        }
    }

    /// @inheritdoc ICSParametersRegistry
    function getStrikesParams(
        uint256 curveId
    ) external view returns (uint256 lifetime, uint256 threshold) {
        StrikesParams storage params = _strikesParams[curveId];
        if (params.threshold == 0) {
            return (
                defaultStrikesParams.lifetime,
                defaultStrikesParams.threshold
            );
        }
        return (params.lifetime, params.threshold);
    }

    /// @inheritdoc ICSParametersRegistry
    function getBadPerformancePenalty(
        uint256 curveId
    ) external view returns (uint256 penalty) {
        MarkedUint248 storage data = _badPerformancePenalties[curveId];
        return data.isValue ? data.value : defaultBadPerformancePenalty;
    }

    /// @inheritdoc ICSParametersRegistry
    function getPerformanceCoefficients(
        uint256 curveId
    )
        external
        view
        returns (
            uint256 attestationsWeight,
            uint256 blocksWeight,
            uint256 syncWeight
        )
    {
        PerformanceCoefficients storage coefficients = _performanceCoefficients[
            curveId
        ];
        if (
            coefficients.attestationsWeight == 0 &&
            coefficients.blocksWeight == 0 &&
            coefficients.syncWeight == 0
        ) {
            return (
                defaultPerformanceCoefficients.attestationsWeight,
                defaultPerformanceCoefficients.blocksWeight,
                defaultPerformanceCoefficients.syncWeight
            );
        }
        return (
            coefficients.attestationsWeight,
            coefficients.blocksWeight,
            coefficients.syncWeight
        );
    }

    /// @inheritdoc ICSParametersRegistry
    function getAllowedExitDelay(
        uint256 curveId
    ) external view returns (uint256 delay) {
        delay = _allowedExitDelay[curveId];
        if (delay == 0) {
            return defaultAllowedExitDelay;
        }
    }

    /// @inheritdoc ICSParametersRegistry
    function getExitDelayFee(
        uint256 curveId
    ) external view returns (uint256 penalty) {
        MarkedUint248 memory data = _exitDelayFees[curveId];
        return data.isValue ? data.value : defaultExitDelayFee;
    }

    /// @inheritdoc ICSParametersRegistry
    function getMaxWithdrawalRequestFee(
        uint256 curveId
    ) external view returns (uint256 fee) {
        MarkedUint248 memory data = _maxWithdrawalRequestFees[curveId];
        return data.isValue ? data.value : defaultMaxWithdrawalRequestFee;
    }

    /// @inheritdoc ICSParametersRegistry
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Internal functions
    ////////////////////////////////////////////////////////////////////////////////

    function _setDefaultKeyRemovalCharge(uint256 keyRemovalCharge) internal {
        defaultKeyRemovalCharge = keyRemovalCharge;
        emit DefaultKeyRemovalChargeSet(keyRemovalCharge);
    }

    function _setDefaultGeneralDelayedPenaltyAdditionalFine(
        uint256 fine
    ) internal {
        defaultGeneralDelayedPenaltyAdditionalFine = fine;
        emit DefaultGeneralDelayedPenaltyAdditionalFineSet(fine);
    }

    function _setDefaultKeysLimit(uint256 limit) internal {
        defaultKeysLimit = limit;
        emit DefaultKeysLimitSet(limit);
    }

    function _setDefaultRewardShare(uint256 share) internal {
        if (share > MAX_BP) {
            revert InvalidRewardShareData();
        }

        defaultRewardShare = share;
        emit DefaultRewardShareSet(share);
    }

    function _setDefaultPerformanceLeeway(uint256 leeway) internal {
        if (leeway > MAX_BP) {
            revert InvalidPerformanceLeewayData();
        }

        defaultPerformanceLeeway = leeway;
        emit DefaultPerformanceLeewaySet(leeway);
    }

    function _setDefaultStrikesParams(
        uint256 lifetime,
        uint256 threshold
    ) internal {
        _validateStrikesParams(lifetime, threshold);
        defaultStrikesParams = StrikesParams({
            lifetime: lifetime.toUint32(),
            threshold: threshold.toUint32()
        });
        emit DefaultStrikesParamsSet(lifetime, threshold);
    }

    function _setDefaultBadPerformancePenalty(uint256 penalty) internal {
        defaultBadPerformancePenalty = penalty;
        emit DefaultBadPerformancePenaltySet(penalty);
    }

    function _setDefaultPerformanceCoefficients(
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) internal {
        _validatePerformanceCoefficients(
            attestationsWeight,
            blocksWeight,
            syncWeight
        );
        defaultPerformanceCoefficients = PerformanceCoefficients({
            attestationsWeight: attestationsWeight.toUint32(),
            blocksWeight: blocksWeight.toUint32(),
            syncWeight: syncWeight.toUint32()
        });
        emit DefaultPerformanceCoefficientsSet(
            attestationsWeight,
            blocksWeight,
            syncWeight
        );
    }

    function _setDefaultQueueConfig(
        uint256 priority,
        uint256 maxDeposits
    ) internal {
        _validateQueueConfig(priority, maxDeposits);
        defaultQueueConfig = QueueConfig({
            priority: priority.toUint32(),
            maxDeposits: maxDeposits.toUint32()
        });
        emit DefaultQueueConfigSet(priority, maxDeposits);
    }

    function _setDefaultAllowedExitDelay(uint256 delay) internal {
        _validateAllowedExitDelay(delay);
        defaultAllowedExitDelay = delay;
        emit DefaultAllowedExitDelaySet(delay);
    }

    function _setDefaultExitDelayFee(uint256 penalty) internal {
        defaultExitDelayFee = penalty;
        emit DefaultExitDelayFeeSet(penalty);
    }

    function _setDefaultMaxWithdrawalRequestFee(uint256 fee) internal {
        defaultMaxWithdrawalRequestFee = fee;
        emit DefaultMaxWithdrawalRequestFeeSet(fee);
    }

    function _validateQueueConfig(
        uint256 priority,
        uint256 maxDeposits
    ) internal view {
        if (priority > QUEUE_LOWEST_PRIORITY) {
            revert QueueCannotBeUsed();
        }
        if (maxDeposits == 0) {
            revert ZeroMaxDeposits();
        }
    }

    function _validateStrikesParams(
        uint256 lifetime,
        uint256 threshold
    ) internal pure {
        if (threshold == 0 || lifetime == 0) {
            revert InvalidStrikesParams();
        }
    }

    function _validateAllowedExitDelay(uint256 delay) internal pure {
        if (delay == 0) {
            revert InvalidAllowedExitDelay();
        }
    }

    function _validatePerformanceCoefficients(
        uint256 attestationsWeight,
        uint256 blocksWeight,
        uint256 syncWeight
    ) internal pure {
        if (attestationsWeight == 0 && blocksWeight == 0 && syncWeight == 0) {
            revert InvalidPerformanceCoefficients();
        }
    }

    function _validateKeyNumberValueIntervals(
        KeyNumberValueInterval[] calldata intervals
    ) private pure {
        if (intervals.length == 0) {
            revert InvalidKeyNumberValueIntervals();
        }
        if (intervals[0].minKeyNumber != 1) {
            revert InvalidKeyNumberValueIntervals();
        }

        if (intervals[0].value > MAX_BP) {
            revert InvalidKeyNumberValueIntervals();
        }

        for (uint256 i = 1; i < intervals.length; ++i) {
            unchecked {
                if (
                    intervals[i].minKeyNumber <= intervals[i - 1].minKeyNumber
                ) {
                    revert InvalidKeyNumberValueIntervals();
                }
                if (intervals[i].value > MAX_BP) {
                    revert InvalidKeyNumberValueIntervals();
                }
            }
        }
    }
}
