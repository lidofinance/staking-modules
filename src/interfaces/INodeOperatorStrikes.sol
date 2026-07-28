// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @dev Payload describing a strike to issue.
struct StrikeInput {
    uint256 nodeOperatorId;
    bytes32 category;
    uint256 lifetime;
    string description;
}

/// @dev Stored strike record (kept in a mapping by id, so the struct can grow without migration).
///      A live strike has `expiry != 0`; a removed or never-issued one reads as zeroed.
struct Strike {
    uint64 id;
    uint64 expiry;
    bytes32 category;
    string description;
}

/// @dev Cumulative weight reduction step. At `minCount` active strikes the operator's weight is
///      reduced by `reductionBP` basis points (effective multiplier = MAX_BP - reductionBP).
struct StrikeThreshold {
    uint128 minCount;
    uint128 reductionBP;
}

/// @notice Committee-issued strikes act as a weight-reduction provider consumed by MetaRegistry.
interface INodeOperatorStrikes is IWeightBoostProvider {
    event StrikeIssued(
        uint256 indexed nodeOperatorId,
        uint256 indexed strikeId,
        bytes32 indexed category,
        uint256 expiry,
        string description
    );
    event StrikeRemoved(uint256 indexed nodeOperatorId, uint256 indexed strikeId);
    event ExpiredStrikeRemoved(uint256 indexed nodeOperatorId, uint256 indexed strikeId);
    event StrikeThresholdsSet(StrikeThreshold[] thresholds);

    error ZeroModuleAddress();
    error ZeroAdminAddress();
    error NodeOperatorDoesNotExist();
    error StrikeNotExist();
    error ZeroLifetime();
    error LifetimeTooLong();
    error InvalidStrikeThresholds();
    error InvalidDescription();

    /// @notice Role allowed to issue and remove strikes.
    function STRIKES_COMMITTEE_ROLE() external view returns (bytes32);

    /// @notice Maximum number of weight-reduction thresholds.
    function MAX_THRESHOLDS() external view returns (uint256);

    /// @notice Maximum byte length of a strike description.
    function MAX_DESCRIPTION_LENGTH() external view returns (uint256);

    /// @notice Curated module used to check operator existence.
    function MODULE() external view returns (ICuratedModule);

    /// @notice MetaRegistry called back via `notifyWeightBoostChanged` on every strike change.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice Initialize the contract.
    /// @param admin      Address to receive DEFAULT_ADMIN_ROLE.
    /// @param thresholds Initial weight-reduction thresholds.
    function initialize(address admin, StrikeThreshold[] calldata thresholds) external;

    /// @notice Issue a strike against a Node Operator (callable by STRIKES_COMMITTEE_ROLE).
    /// @param input Strike payload.
    /// @return strikeId ID assigned to the new strike.
    function issueStrike(StrikeInput calldata input) external returns (uint256 strikeId);

    /// @notice Remove any strike (callable by STRIKES_COMMITTEE_ROLE). For permissionless cleanup of
    ///         expired strikes use `removeExpiredStrikes`.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId       ID of the strike to remove.
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external;

    /// @notice Permissionlessly remove all of a Node Operator's strikes whose lifetime has elapsed.
    ///         No-op if none are expired.
    /// @param nodeOperatorId ID of the Node Operator.
    function removeExpiredStrikes(uint256 nodeOperatorId) external;

    /// @notice Set the global weight-reduction thresholds (callable by DEFAULT_ADMIN_ROLE).
    /// @dev Notifies MetaRegistry of the config change so affected operator weights are refreshed.
    /// @param thresholds Step function mapping active strike count to weight reduction.
    function setStrikeThresholds(StrikeThreshold[] calldata thresholds) external;

    /// @notice Number of active (non-removed) strikes of a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    function getActiveStrikesCount(uint256 nodeOperatorId) external view returns (uint256 count);

    /// @notice Return a single strike record. Reverts with `StrikeNotExist` if removed or never issued.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId       ID of the strike.
    function getStrike(uint256 nodeOperatorId, uint256 strikeId) external view returns (Strike memory strike);

    /// @notice Return all of a Node Operator's active (non-removed) strikes.
    /// @param nodeOperatorId ID of the Node Operator.
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes);

    /// @notice Return the configured global weight-reduction thresholds.
    function getStrikeThresholds() external view returns (StrikeThreshold[] memory thresholds);
}
