// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { IMetaRegistry } from "../interfaces/IMetaRegistry.sol";
import { ICuratedModule } from "../interfaces/ICuratedModule.sol";
import { IStepwiseWeightBoost, Step } from "../interfaces/IStepwiseWeightBoost.sol";
import { MAX_BP } from "../lib/Constants.sol";

/// @notice Shared base of the weight boost providers built on a governance-configurable step function.
abstract contract StepwiseWeightBoost is IStepwiseWeightBoost, AccessControlEnumerableUpgradeable {
    /// @custom:storage-location erc7201:StepwiseWeightBoost
    struct StepwiseWeightBoostStorage {
        Step[] steps;
    }

    ICuratedModule public immutable MODULE;
    IMetaRegistry public immutable META_REGISTRY;

    uint256 public constant MAX_STEPS = 35;
    uint256 public constant MAX_STEP_VALUE = 9 * MAX_BP;

    // keccak256(abi.encode(uint256(keccak256("StepwiseWeightBoost")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STEPWISE_WEIGHT_BOOST_STORAGE_LOCATION =
        0x852fd528c3d50d3563ef75d3ae6120a75c34ba905ef4b17904bd8502a3b92900;

    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();
        MODULE = ICuratedModule(module);
        META_REGISTRY = IMetaRegistry(address(MODULE.META_REGISTRY()));

        _disableInitializers();
    }

    /// @inheritdoc IStepwiseWeightBoost
    function setSteps(Step[] calldata steps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setSteps(steps);
        META_REGISTRY.notifyWeightBoostProviderConfigChanged();
    }

    /// @inheritdoc IStepwiseWeightBoost
    function getSteps() external view returns (Step[] memory) {
        return _stepwiseWeightBoostStorage().steps;
    }

    /// @inheritdoc IStepwiseWeightBoost
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @dev Unlike `setSteps`, does not notify MetaRegistry: there are no cached weights yet.
    function _initialize(address admin, Step[] calldata steps) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setSteps(steps);
    }

    /// @dev Skips the refresh while the input stays within one step: the weight has not moved.
    function _notifyMetaRegistryIfWeightChanged(
        uint256 nodeOperatorId,
        uint256 previousInput,
        uint256 newInput
    ) internal {
        if (_stepValueAt(previousInput) != _stepValueAt(newInput)) {
            META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
        }
    }

    /// @dev Reverts unless the Node Operator exists and the caller owns it.
    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert SenderIsNotNodeOperatorOwner();
    }

    /// @dev Ids are sequential, so an id below the operators count exists.
    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId >= MODULE.getNodeOperatorsCount()) revert NodeOperatorDoesNotExist();
    }

    /// @dev Returns zero before the first threshold and the last reached step's value otherwise.
    function _stepValueAt(uint256 input) internal view returns (uint256 value) {
        Step[] storage steps = _stepwiseWeightBoostStorage().steps;
        uint256 low;
        uint256 high = steps.length;

        // Find the first step whose threshold is greater than the input.
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (steps[mid].threshold <= input) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        if (low != 0) value = steps[low - 1].value;
    }

    /// @dev Provider-specific bounds, including any ceiling stricter than MAX_STEP_VALUE. Ordering is
    ///      enforced by the base contract.
    function _isValidStep(Step calldata step) internal pure virtual returns (bool);

    function _setSteps(Step[] calldata steps) private {
        uint256 length = steps.length;
        if (length == 0 || length > MAX_STEPS) revert InvalidStepCount();

        for (uint256 i; i < length; ++i) {
            if (steps[i].value > MAX_STEP_VALUE || !_isValidStep(steps[i])) revert InvalidStep(i);
            if (i != 0 && (steps[i].threshold <= steps[i - 1].threshold || steps[i].value <= steps[i - 1].value))
                revert UnorderedSteps(i);
        }

        StepwiseWeightBoostStorage storage $ = _stepwiseWeightBoostStorage();
        delete $.steps;
        for (uint256 i; i < length; ++i) {
            $.steps.push(steps[i]);
        }
        emit StepsSet(steps);
    }

    function _stepwiseWeightBoostStorage() private pure returns (StepwiseWeightBoostStorage storage $) {
        assembly ("memory-safe") {
            $.slot := STEPWISE_WEIGHT_BOOST_STORAGE_LOCATION
        }
    }
}
