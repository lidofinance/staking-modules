// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";

/// @dev Payload describing a strike to issue. For the stored `description` see `getStrikeDescription`.
struct StrikeInput {
    uint256 nodeOperatorId;
    bytes32 category;
    uint256 lifetime;
    string description;
}

/// @dev Removed or never-issued strike reads as a zeroed slot (`id == 0`).
struct Strike {
    uint64 id;
    uint64 expiry;
    bytes32 category;
}

/// @dev Cumulative weight reduction step. At `minCount` active strikes the operator's weight is
///      reduced by `reductionBP` basis points (effective multiplier = MAX_BP - reductionBP).
struct StrikeThreshold {
    uint256 minCount;
    uint256 reductionBP;
}

interface INodeOperatorStrikes {
    event StrikeIssued(
        uint256 indexed nodeOperatorId,
        uint256 indexed strikeId,
        bytes32 indexed category,
        uint256 expiry,
        string description
    );
    event StrikeRemoved(uint256 indexed nodeOperatorId, uint256 indexed strikeId, address indexed remover);
    event StrikeThresholdsSet(StrikeThreshold[] thresholds);

    error ZeroModuleAddress();
    error ZeroAdminAddress();
    error NodeOperatorDoesNotExist();
    error StrikeNotExist();
    error InvalidLifetime();
    error InvalidStrikeThresholds();
    error DescriptionTooLong();

    /// @notice Role allowed to issue and remove strikes.
    function STRIKES_COMMITTEE_ROLE() external view returns (bytes32);

    /// @notice Maximum number of weight-reduction thresholds.
    function MAX_THRESHOLDS() external view returns (uint256);

    /// @notice Maximum byte length of a strike description.
    function MAX_DESCRIPTION_LENGTH() external view returns (uint256);

    /// @notice Curated module used to check operator existence.
    function MODULE() external view returns (ICuratedModule);

    /// @notice MetaRegistry called back via `refreshOperatorWeight` on every strike change.
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
    /// @dev MUST be paired with `MetaRegistry.refreshOperatorWeight` for every operator with active strikes.
    /// @param thresholds Step function mapping active strike count to weight reduction.
    function setStrikeThresholds(StrikeThreshold[] calldata thresholds) external;

    /// @notice Number of active (non-removed) strikes of a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    function getActiveStrikesCount(uint256 nodeOperatorId) external view returns (uint256 count);

    /// @notice Weight multiplier (in basis points) implied by the operator's active strike count.
    /// @dev Counts strikes regardless of expiry: an expired strike keeps reducing the weight until removed.
    /// @param nodeOperatorId ID of the Node Operator.
    function getStrikeWeightMultiplier(uint256 nodeOperatorId) external view returns (uint256 multiplierBP);

    /// @notice Return a single strike record. Reverts with `StrikeNotExist` if removed or never issued.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId       ID of the strike.
    function getStrike(uint256 nodeOperatorId, uint256 strikeId) external view returns (Strike memory strike);

    /// @notice On-chain description of a strike. Reverts with `StrikeNotExist` if removed or never issued.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param strikeId       ID of the strike.
    function getStrikeDescription(
        uint256 nodeOperatorId,
        uint256 strikeId
    ) external view returns (string memory description);

    /// @notice Return the active (non-removed) strikes of a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes);

    /// @notice Return the configured global weight-reduction thresholds.
    function getStrikeThresholds() external view returns (StrikeThreshold[] memory thresholds);
}
