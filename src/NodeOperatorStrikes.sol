// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { INodeOperatorStrikes, StrikeInput, Strike } from "./interfaces/INodeOperatorStrikes.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Committee-issued, operator-level strikes that cumulatively reduce
///         a Node Operator's allocation weight. Strikes persist until removed;
///         removal is permissionless once a strike's lifetime elapses.
contract NodeOperatorStrikes is INodeOperatorStrikes, StepwiseWeightBoost {
    struct OperatorStrikes {
        /// @dev Monotonic strike ID counter; removed IDs are never reused.
        uint64 lastId;
        /// @dev IDs of non-removed strikes, used for enumeration, counting, and swap-pop removal.
        uint256[] activeIds;
        mapping(uint256 strikeId => Strike) strikes;
    }

    /// @custom:storage-location erc7201:NodeOperatorStrikes
    struct NodeOperatorStrikesStorage {
        mapping(uint256 nodeOperatorId => OperatorStrikes) operatorStrikes;
    }

    bytes32 public constant STRIKES_COMMITTEE_ROLE = keccak256("STRIKES_COMMITTEE_ROLE");

    uint256 public constant MAX_DESCRIPTION_LENGTH = 1024;

    // keccak256(abi.encode(uint256(keccak256("NodeOperatorStrikes")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NODE_OPERATOR_STRIKES_STORAGE_LOCATION =
        0x510f8e4bbf34090117edc1d950679ffb8abd223dc216175d997628968b892400;

    /// @param module CuratedModule proxy address.
    constructor(address module) StepwiseWeightBoost(module) {}

    /// @inheritdoc INodeOperatorStrikes
    function initialize(address admin, Step[] calldata steps) external initializer {
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc INodeOperatorStrikes
    function issueStrike(
        StrikeInput calldata input
    ) external onlyRole(STRIKES_COMMITTEE_ROLE) returns (uint256 strikeId) {
        StepwiseWeightBoost._onlyExistingNodeOperator(input.nodeOperatorId);

        uint256 descLength = bytes(input.description).length;
        if (descLength == 0 || descLength > MAX_DESCRIPTION_LENGTH) revert InvalidDescription();

        uint256 lifetime = input.lifetime;
        if (lifetime == 0) revert ZeroLifetime();
        uint256 expiry = block.timestamp + lifetime;
        if (expiry > type(uint64).max) revert LifetimeTooLong();

        OperatorStrikes storage rec = _storage().operatorStrikes[input.nodeOperatorId];
        uint256 previousCount = rec.activeIds.length;
        strikeId = ++rec.lastId;
        rec.activeIds.push(strikeId);
        rec.strikes[strikeId] = Strike({
            id: uint64(strikeId),
            expiry: uint64(expiry),
            category: input.category,
            description: input.description
        });

        emit StrikeIssued({
            nodeOperatorId: input.nodeOperatorId,
            strikeId: strikeId,
            category: input.category,
            expiry: expiry,
            description: input.description
        });

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(input.nodeOperatorId, previousCount, previousCount + 1);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external onlyRole(STRIKES_COMMITTEE_ROLE) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        uint256 previousCount = rec.activeIds.length;
        _removeStrike(rec, _activeIndex(rec, strikeId), strikeId);
        emit StrikeRemoved(nodeOperatorId, strikeId);

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, previousCount, previousCount - 1);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeExpiredStrikes(uint256 nodeOperatorId) external {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        uint256[] storage activeIds = rec.activeIds;
        uint256 previousCount = activeIds.length;

        // Back-to-front so swap-pop never skips an id.
        uint256 i = activeIds.length;
        while (i > 0) {
            --i;
            uint256 strikeId = activeIds[i];
            if (rec.strikes[strikeId].expiry > block.timestamp) continue;
            _removeStrike(rec, i, strikeId);
            emit ExpiredStrikeRemoved(nodeOperatorId, strikeId);
        }

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, previousCount, activeIds.length);
    }

    /// @inheritdoc IWeightBoostProvider
    /// @dev Expiry only enables permissionless removal; a strike keeps reducing weight until it is removed.
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        uint256 count = _storage().operatorStrikes[nodeOperatorId].activeIds.length;
        unchecked {
            multiplierBP = MAX_BP - StepwiseWeightBoost._stepValueAt(count);
        }
    }

    /// @inheritdoc INodeOperatorStrikes
    function getActiveStrikesCount(uint256 nodeOperatorId) external view returns (uint256 count) {
        return _storage().operatorStrikes[nodeOperatorId].activeIds.length;
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrike(uint256 nodeOperatorId, uint256 strikeId) external view returns (Strike memory strike) {
        strike = _storage().operatorStrikes[nodeOperatorId].strikes[strikeId];
        // expiry == 0 means removed or never issued.
        if (strike.expiry == 0) revert StrikeDoesNotExist();
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        uint256[] storage activeIds = rec.activeIds;
        uint256 len = activeIds.length;

        strikes = new Strike[](len);
        for (uint256 i; i < len; ++i) {
            strikes[i] = rec.strikes[activeIds[i]];
        }
    }

    /// @dev Swap-pops the id and deletes the record. Caller emits and refreshes the weight (once per batch).
    function _removeStrike(OperatorStrikes storage rec, uint256 idx, uint256 strikeId) internal {
        uint256[] storage activeIds = rec.activeIds;
        uint256 lastIdx = activeIds.length - 1;
        if (idx != lastIdx) {
            activeIds[idx] = activeIds[lastIdx];
        }
        activeIds.pop();
        delete rec.strikes[strikeId];
    }

    /// @dev Index of `strikeId` in `activeIds`; reverts `StrikeDoesNotExist` if absent.
    function _activeIndex(OperatorStrikes storage rec, uint256 strikeId) internal view returns (uint256) {
        uint256[] storage activeIds = rec.activeIds;
        uint256 len = activeIds.length;
        for (uint256 i; i < len; ++i) {
            if (activeIds[i] == strikeId) return i;
        }
        revert StrikeDoesNotExist();
    }

    /// @dev A strike reduces weight, so a reduction above MAX_BP could never be applied.
    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold != 0 && step.value != 0 && step.value <= MAX_BP;
    }

    function _storage() internal pure returns (NodeOperatorStrikesStorage storage $) {
        assembly ("memory-safe") {
            $.slot := NODE_OPERATOR_STRIKES_STORAGE_LOCATION
        }
    }
}
