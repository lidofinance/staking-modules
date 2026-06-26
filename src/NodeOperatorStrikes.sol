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
    }

    /// @custom:storage-location erc7201:NodeOperatorStrikes
    struct NodeOperatorStrikesStorage {
        StrikeThreshold[] thresholds;
        mapping(uint256 nodeOperatorId => OperatorStrikes) operatorStrikes;
    }

    bytes32 public constant STRIKES_COMMITTEE_ROLE = keccak256("STRIKES_COMMITTEE_ROLE");

    uint256 public constant MAX_THRESHOLDS = 16;

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
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc INodeOperatorStrikes
    function issueStrike(
        StrikeInput calldata input
    ) external onlyRole(STRIKES_COMMITTEE_ROLE) returns (uint256 strikeId) {
        return _issueStrike(input);
    }

    /// @inheritdoc INodeOperatorStrikes
    function removeStrike(uint256 nodeOperatorId, uint256 strikeId) external {
        _removeStrike(nodeOperatorId, strikeId);
    }

    /// @inheritdoc INodeOperatorStrikes
    function setStrikeThresholds(StrikeThreshold[] calldata thresholds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validateStrikeThresholds(thresholds);

        StrikeThreshold[] storage stored = _storage().thresholds;
        if (stored.length > 0) delete _storage().thresholds;
        for (uint256 i; i < thresholds.length; ++i) {
            stored.push(thresholds[i]);
        }

        emit StrikeThresholdsSet(thresholds);
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
        uint256 position = rec.index[strikeId];
        if (position == 0) return strike;
        return rec.active[position - 1];
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikes(uint256 nodeOperatorId) external view returns (Strike[] memory strikes) {
        return _storage().operatorStrikes[nodeOperatorId].active;
    }

    /// @inheritdoc INodeOperatorStrikes
    function getExpiredStrikes(uint256 nodeOperatorId) external view returns (uint256[] memory strikeIds) {
        Strike[] storage active = _storage().operatorStrikes[nodeOperatorId].active;
        uint256 len = active.length;

        strikeIds = new uint256[](len);
        uint256 j;
        for (uint256 i; i < len; ++i) {
            if (active[i].expiry <= block.timestamp) {
                strikeIds[j] = active[i].id;
                ++j;
            }
        }

        assembly ("memory-safe") {
            mstore(strikeIds, j)
        }
    }

    /// @inheritdoc INodeOperatorStrikes
    function getStrikeThresholds() external view returns (StrikeThreshold[] memory thresholds) {
        return _storage().thresholds;
    }

    function _issueStrike(StrikeInput calldata input) internal returns (uint256 strikeId) {
        _onlyExistingOperator(input.nodeOperatorId);

        uint256 lifetime = input.lifetime;
        if (lifetime == 0) revert InvalidLifetime();
        uint256 expiry = block.timestamp + lifetime;
        if (expiry > type(uint64).max) revert InvalidLifetime();

        // TODO: consider a MAX_STRIKES_PER_OPERATOR cap; past the deepest threshold weight is already 0.
        OperatorStrikes storage rec = _storage().operatorStrikes[input.nodeOperatorId];
        strikeId = ++rec.lastStrikeId;
        rec.active.push(Strike({ id: uint64(strikeId), expiry: uint64(expiry), category: input.category }));
        rec.index[strikeId] = rec.active.length;

        emit StrikeIssued({
            nodeOperatorId: input.nodeOperatorId,
            strikeId: strikeId,
            category: input.category,
            expiry: expiry,
            name: input.name,
            description: input.description
        });

        META_REGISTRY.refreshOperatorWeight(input.nodeOperatorId);
    }

    function _removeStrike(uint256 nodeOperatorId, uint256 strikeId) internal {
        OperatorStrikes storage rec = _storage().operatorStrikes[nodeOperatorId];
        uint256 position = rec.index[strikeId];
        if (position == 0) revert StrikeNotActive();

        uint256 idx = position - 1;
        // Committee may remove anytime; anyone else only after the lifetime elapses.
        if (!hasRole(STRIKES_COMMITTEE_ROLE, msg.sender) && rec.active[idx].expiry > block.timestamp) {
            revert StrikeNotExpired();
        }

        uint256 lastIdx = rec.active.length - 1;
        if (idx != lastIdx) {
            Strike memory moved = rec.active[lastIdx];
            rec.active[idx] = moved;
            rec.index[moved.id] = position;
        }
        rec.active.pop();
        delete rec.index[strikeId];

        emit StrikeRemoved(nodeOperatorId, strikeId, msg.sender);

        META_REGISTRY.refreshOperatorWeight(nodeOperatorId);
    }

    function _onlyExistingOperator(uint256 nodeOperatorId) internal view {
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
            if (thresholds[i].reductionBP < thresholds[i - 1].reductionBP) revert InvalidStrikeThresholds();
            if (thresholds[i].reductionBP > MAX_BP) revert InvalidStrikeThresholds();
        }
    }
}
