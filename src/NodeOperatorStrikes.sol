// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { INodeOperatorStrikes, StrikeInput, Strike, StrikeThreshold } from "./interfaces/INodeOperatorStrikes.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Committee-issued, operator-level strikes that cumulatively reduce
///         a Node Operator's allocation weight. Strikes persist until removed;
///         removal is permissionless once a strike's lifetime elapses.
contract NodeOperatorStrikes is INodeOperatorStrikes, Initializable, AccessControlEnumerableUpgradeable {
    struct OperatorStrikes {
        uint64 lastId;
        uint256[] activeIds;
        mapping(uint256 strikeId => Strike) strikes;
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

        uint256 descLength = bytes(input.description).length;
        if (descLength == 0 || descLength > MAX_DESCRIPTION_LENGTH) revert InvalidDescription();

        uint256 lifetime = input.lifetime;
        if (lifetime == 0) revert ZeroLifetime();
        if (block.timestamp > type(uint64).max || lifetime > type(uint64).max - block.timestamp) {
            revert LifetimeTooLong();
        }
        uint256 expiry = block.timestamp + lifetime;

        OperatorStrikes storage rec = _storage().operatorStrikes[input.nodeOperatorId];
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

        META_REGISTRY.notifyWeightBoostChanged(input.nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external onlyRole(STRIKES_COMMITTEE_ROLE) {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        _removeStrike(rec, nodeOperatorId, _activeIndex(rec, strikeId), strikeId);

        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeExpiredStrikes(uint256 nodeOperatorId) external {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        uint256[] storage activeIds = rec.activeIds;

        // Back-to-front so swap-pop never skips an id.
        bool removed;
        uint256 i = activeIds.length;
        while (i > 0) {
            --i;
            uint256 strikeId = activeIds[i];
            if (rec.strikes[strikeId].expiry > block.timestamp) continue;
            _removeStrike(rec, nodeOperatorId, i, strikeId);
            removed = true;
        }

        if (removed) META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function setStrikeThresholds(StrikeThreshold[] calldata thresholds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setStrikeThresholds(thresholds);
        META_REGISTRY.notifyWeightBoostProviderConfigChanged();
    }

    /// @inheritdoc IWeightBoostProvider
    /// @dev Counts strikes regardless of expiry: an expired one keeps reducing the weight until removed.
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = MAX_BP;

        NodeOperatorStrikesStorage storage $ = _storage();
        uint256 count = $.operatorStrikes[nodeOperatorId].activeIds.length;

        StrikeThreshold[] storage thresholds = $.thresholds;
        uint256 len = thresholds.length;
        for (uint256 i; i < len; ++i) {
            if (count < thresholds[i].minCount) break; // thresholds ascend by minCount
            multiplierBP = MAX_BP - thresholds[i].reductionBP;
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
        if (strike.expiry == 0) revert StrikeNotExist();
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

    /// @inheritdoc INodeOperatorStrikes
    function getStrikeThresholds() external view returns (StrikeThreshold[] memory thresholds) {
        return _storage().thresholds;
    }

    /// @dev Swap-pops the id, deletes the record, emits. Caller refreshes the weight (once per batch).
    function _removeStrike(
        OperatorStrikes storage rec,
        uint256 nodeOperatorId,
        uint256 idx,
        uint256 strikeId
    ) internal {
        uint256[] storage activeIds = rec.activeIds;
        uint256 lastIdx = activeIds.length - 1;
        if (idx != lastIdx) {
            activeIds[idx] = activeIds[lastIdx];
        }
        activeIds.pop();
        delete rec.strikes[strikeId];

        emit StrikeRemoved(nodeOperatorId, strikeId, msg.sender);
    }

    function _setStrikeThresholds(StrikeThreshold[] calldata thresholds) internal {
        _validateStrikeThresholds(thresholds);

        NodeOperatorStrikesStorage storage $ = _storage();
        delete $.thresholds;
        for (uint256 i; i < thresholds.length; ++i) {
            $.thresholds.push(thresholds[i]);
        }

        emit StrikeThresholdsSet(thresholds);
    }

    function _onlyExistingOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId >= MODULE.getNodeOperatorsCount()) revert NodeOperatorDoesNotExist();
    }

    /// @dev Index of `strikeId` in `activeIds`; reverts `StrikeNotExist` if absent.
    function _activeIndex(OperatorStrikes storage rec, uint256 strikeId) internal view returns (uint256) {
        uint256[] storage activeIds = rec.activeIds;
        uint256 len = activeIds.length;
        for (uint256 i; i < len; ++i) {
            if (activeIds[i] == strikeId) return i;
        }
        revert StrikeNotExist();
    }

    function _validateStrikeThresholds(StrikeThreshold[] calldata thresholds) internal pure {
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

    function _storage() internal pure returns (NodeOperatorStrikesStorage storage $) {
        assembly ("memory-safe") {
            $.slot := NODE_OPERATOR_STRIKES_STORAGE_LOCATION
        }
    }
}
