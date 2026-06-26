// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { INodeOperatorStrikes, StrikeInput, Strike, StrikeThreshold } from "./interfaces/INodeOperatorStrikes.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Committee-issued, operator-level strikes that cumulatively reduce
///         a Node Operator's allocation weight. Strikes persist until removed;
///         removal is permissionless once a strike's lifetime elapses.
contract NodeOperatorStrikes is INodeOperatorStrikes, Initializable, AccessControlEnumerableUpgradeable {
    struct OperatorStrikes {
        uint64 lastStrikeId;
        Strike[] active;
        /// @dev maps a strike id to its position in `active` (0 = not active).
        mapping(uint256 strikeId => uint256 position) index;
        /// @dev on-chain strike description; cleared on removal (empty if removed or never issued).
        mapping(uint256 strikeId => string description) descriptions;
    }

    /// @custom:storage-location erc7201:NodeOperatorStrikes
    struct NodeOperatorStrikesStorage {
        StrikeThreshold[] thresholds;
        mapping(uint256 nodeOperatorId => OperatorStrikes) operatorStrikes;
    }

    bytes32 public constant STRIKES_COMMITTEE_ROLE = keccak256("STRIKES_COMMITTEE_ROLE");

    uint256 public constant MAX_THRESHOLDS = 16;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1024;

    ICuratedModule public immutable MODULE;
    IMetaRegistry public immutable META_REGISTRY;

    // keccak256(abi.encode(uint256(keccak256("NodeOperatorStrikes")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NODE_OPERATOR_STRIKES_STORAGE_LOCATION =
        0x510f8e4bbf34090117edc1d950679ffb8abd223dc216175d997628968b892400;

    /// @param module CuratedModule proxy address.
    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();

        MODULE = ICuratedModule(module);
        META_REGISTRY = ICuratedModule(module).META_REGISTRY();

        _disableInitializers();
    }

    /// @inheritdoc INodeOperatorStrikes
    function initialize(address admin, StrikeThreshold[] calldata thresholds) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setStrikeThresholds(thresholds);
    }

    /// @inheritdoc INodeOperatorStrikes
    function issueStrike(
        StrikeInput calldata input
    ) external onlyRole(STRIKES_COMMITTEE_ROLE) returns (uint256 strikeId) {
        _onlyExistingOperator(input.nodeOperatorId);

        if (bytes(input.description).length > MAX_DESCRIPTION_LENGTH) revert DescriptionTooLong();

        uint256 lifetime = input.lifetime;
        if (lifetime == 0) revert InvalidLifetime();
        uint256 expiry = block.timestamp + lifetime;
        if (expiry > type(uint64).max) revert InvalidLifetime();

        OperatorStrikes storage rec = _storage().operatorStrikes[input.nodeOperatorId];
        strikeId = ++rec.lastStrikeId;
        rec.active.push(Strike({ id: uint64(strikeId), expiry: uint64(expiry), category: input.category }));
        rec.index[strikeId] = rec.active.length;
        rec.descriptions[strikeId] = input.description;

        emit StrikeIssued({
            nodeOperatorId: input.nodeOperatorId,
            strikeId: strikeId,
            category: input.category,
            expiry: expiry,
            description: input.description
        });

        META_REGISTRY.refreshOperatorWeight(input.nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external onlyRole(STRIKES_COMMITTEE_ROLE) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        _ensureStrikeExists(rec, strikeId);
        _popStrike(rec, nodeOperatorId, rec.index[strikeId] - 1, strikeId);

        META_REGISTRY.refreshOperatorWeight(nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeExpiredStrikes(uint256 nodeOperatorId) external {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];

        // Back-to-front: swap-pop only moves an already-kept strike down, so none are skipped.
        bool removed;
        uint256 i = rec.active.length;
        while (i > 0) {
            --i;
            if (rec.active[i].expiry > block.timestamp) continue;
            _popStrike(rec, nodeOperatorId, i, rec.active[i].id);
            removed = true;
        }

        if (removed) META_REGISTRY.refreshOperatorWeight(nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function setStrikeThresholds(StrikeThreshold[] calldata thresholds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setStrikeThresholds(thresholds);
    }

    /// @inheritdoc INodeOperatorStrikes
    function getActiveStrikesCount(uint256 nodeOperatorId) external view returns (uint256 count) {
        return _storage().operatorStrikes[nodeOperatorId].active.length;
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikeWeightMultiplier(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = MAX_BP;

        NodeOperatorStrikesStorage storage $ = _storage();
        uint256 count = $.operatorStrikes[nodeOperatorId].active.length;

        StrikeThreshold[] storage thresholds = $.thresholds;
        uint256 len = thresholds.length;
        for (uint256 i; i < len; ++i) {
            if (count < thresholds[i].minCount) break; // thresholds ascend by minCount
            multiplierBP = MAX_BP - thresholds[i].reductionBP;
        }
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrike(uint256 nodeOperatorId, uint256 strikeId) external view returns (Strike memory strike) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        _ensureStrikeExists(rec, strikeId);
        return rec.active[rec.index[strikeId] - 1];
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikeDescription(
        uint256 nodeOperatorId,
        uint256 strikeId
    ) external view returns (string memory description) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        _ensureStrikeExists(rec, strikeId);
        return rec.descriptions[strikeId];
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes) {
        return _storage().operatorStrikes[nodeOperatorId].active;
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikeThresholds() external view returns (StrikeThreshold[] memory thresholds) {
        return _storage().thresholds;
    }

    /// @dev Reverts `StrikeNotExist` if the strike is removed or was never issued.
    function _ensureStrikeExists(OperatorStrikes storage rec, uint256 strikeId) private view {
        if (rec.index[strikeId] == 0) revert StrikeNotExist();
    }

    /// @dev Swap-pops the strike at `idx` and clears its bookkeeping. Caller refreshes the weight.
    function _popStrike(OperatorStrikes storage rec, uint256 nodeOperatorId, uint256 idx, uint256 strikeId) private {
        uint256 lastIdx = rec.active.length - 1;
        if (idx != lastIdx) {
            Strike memory moved = rec.active[lastIdx];
            rec.active[idx] = moved;
            rec.index[moved.id] = idx + 1; // 1-based position
        }
        rec.active.pop();
        delete rec.index[strikeId];
        delete rec.descriptions[strikeId];

        emit StrikeRemoved(nodeOperatorId, strikeId, msg.sender);
    }

    function _setStrikeThresholds(StrikeThreshold[] calldata thresholds) private {
        _validateStrikeThresholds(thresholds);

        delete _storage().thresholds;
        StrikeThreshold[] storage stored = _storage().thresholds;
        for (uint256 i; i < thresholds.length; ++i) {
            stored.push(thresholds[i]);
        }

        emit StrikeThresholdsSet(thresholds);
    }

    function _onlyExistingOperator(uint256 nodeOperatorId) private view {
        if (nodeOperatorId >= MODULE.getNodeOperatorsCount()) revert NodeOperatorDoesNotExist();
    }

    function _storage() internal pure returns (NodeOperatorStrikesStorage storage $) {
        assembly ("memory-safe") {
            $.slot := NODE_OPERATOR_STRIKES_STORAGE_LOCATION
        }
    }

    function _validateStrikeThresholds(StrikeThreshold[] calldata thresholds) private pure {
        uint256 len = thresholds.length;
        if (len == 0 || len > MAX_THRESHOLDS) revert InvalidStrikeThresholds();
        if (thresholds[0].minCount == 0) revert InvalidStrikeThresholds();
        if (thresholds[0].reductionBP > MAX_BP) revert InvalidStrikeThresholds();

        for (uint256 i = 1; i < len; ++i) {
            if (thresholds[i].minCount <= thresholds[i - 1].minCount) revert InvalidStrikeThresholds();
            if (thresholds[i].reductionBP <= thresholds[i - 1].reductionBP) revert InvalidStrikeThresholds();
            if (thresholds[i].reductionBP > MAX_BP) revert InvalidStrikeThresholds();
        }
    }
}
