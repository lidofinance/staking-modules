// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

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

/// @notice Committee-issued strikes act as a weight-reduction provider consumed by MetaRegistry. A strike
///         keeps reducing weight until removed; its expiry only enables permissionless removal. In this
///         provider, `Step.threshold` is the minimum active strike count and `Step.value` is the weight
///         reduction from MAX_BP.
interface INodeOperatorStrikes is IStepwiseWeightBoost {
    event StrikeIssued(
        uint256 indexed nodeOperatorId,
        uint256 indexed strikeId,
        bytes32 indexed category,
        uint256 expiry,
        string description
    );
    event StrikeRemoved(uint256 indexed nodeOperatorId, uint256 indexed strikeId);
    event ExpiredStrikeRemoved(uint256 indexed nodeOperatorId, uint256 indexed strikeId);

    error StrikeDoesNotExist();
    error ZeroLifetime();
    error LifetimeTooLong();
    error InvalidDescription();

    /// @notice Role allowed to issue and remove strikes.
    function STRIKES_COMMITTEE_ROLE() external view returns (bytes32);

    /// @notice Maximum byte length of a strike description.
    function MAX_DESCRIPTION_LENGTH() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param steps Initial steps. Thresholds and values must be nonzero; a value is a weight reduction
    ///        and cannot exceed MAX_BP.
    function initialize(address admin, Step[] calldata steps) external;

    /// @notice Issue a strike against a Node Operator (callable by STRIKES_COMMITTEE_ROLE).
    /// @param input Strike payload.
    /// @return strikeId ID assigned to the new strike.
    function issueStrike(StrikeInput calldata input) external returns (uint256 strikeId);

    /// @notice Remove any strike (callable by STRIKES_COMMITTEE_ROLE). For permissionless cleanup of
    ///         expired strikes use `removeExpiredStrikes`.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId ID of the strike to remove.
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external;

    /// @notice Permissionlessly remove all of a Node Operator's strikes whose lifetime has elapsed.
    ///         No-op if none are expired.
    /// @param nodeOperatorId ID of the Node Operator.
    function removeExpiredStrikes(uint256 nodeOperatorId) external;

    /// @notice Number of active (non-removed) strikes of a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    function getActiveStrikesCount(uint256 nodeOperatorId) external view returns (uint256 count);

    /// @notice Returns a single strike record. Reverts with `StrikeDoesNotExist` if removed or never issued.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId ID of the strike.
    function getStrike(uint256 nodeOperatorId, uint256 strikeId) external view returns (Strike memory strike);

    /// @notice Returns all of a Node Operator's active (non-removed) strikes.
    /// @param nodeOperatorId ID of the Node Operator.
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes);
}
