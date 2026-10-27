// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "./IBaseModule.sol";
import { IStakingModuleV2 } from "./IStakingModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";

interface ICuratedModule is IBaseModule, IStakingModuleV2 {
    event TopUpAllocationEnabled(uint256 indexed nodeOperatorId);
    event TopUpAllocationDisabled(uint256 indexed nodeOperatorId);

    error ZeroMetaRegistryAddress();
    error SenderIsNotMetaRegistry();

    /// @notice Role allowed to enable top-up allocation for node operators.
    function ENABLE_TOP_UP_ALLOCATION_ROLE() external view returns (bytes32);

    /// @notice Initializes the contract.
    /// @param admin An address to grant the DEFAULT_ADMIN_ROLE to.
    function initialize(address admin) external;

    /// @notice Finalizes the upgrade from version 1 to version 2.
    /// @dev Must be called atomically with the proxy upgrade. Fresh deployments use initialize instead.
    ///      Enables top-up allocation for existing operators with totalDepositedKeys > totalWithdrawnKeys.
    function finalizeUpgradeV2() external;

    /// @notice Enables top-up allocation for a node operator.
    /// @param nodeOperatorId ID of the node operator.
    function enableTopUpAllocation(uint256 nodeOperatorId) external;

    /// @notice Disables top-up allocation for a node operator. Only callable by its owner.
    /// @dev Excludes the operator's weight and stake from the executable top-up allocation baseline.
    /// @param nodeOperatorId ID of the node operator.
    function disableTopUpAllocation(uint256 nodeOperatorId) external;

    /// @notice Returns whether top-up allocation is enabled for a node operator.
    /// @param nodeOperatorId ID of the node operator.
    /// @return enabled Whether top-up allocation is enabled.
    function isTopUpAllocationEnabled(uint256 nodeOperatorId) external view returns (bool enabled);

    /// @notice Notifies the module about the weight change of a node operator.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param oldWeight The old weight of the node operator.
    /// @param newWeight The new weight of the node operator.
    function notifyNodeOperatorWeightChange(uint256 nodeOperatorId, uint256 oldWeight, uint256 newWeight) external;

    /// @notice Returns operator weights used for operator-level allocations in the module.
    /// @dev Provides weights from the on-chain allocation strategy used by the module.
    /// @param operatorIds Node operator IDs to query.
    /// @return operatorWeights Weights aligned with operatorIds.
    function getOperatorWeights(
        uint256[] calldata operatorIds
    ) external view returns (uint256[] memory operatorWeights);

    /// @notice Returns effective weight and external stake for a node operator.
    /// @dev Reverts until the module deposit info cache is fully refreshed.
    /// @param nodeOperatorId Node operator ID to query.
    /// @return weight Effective allocation weight.
    /// @return externalStake External stake amount in wei.
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake);

    /// @notice Returns current deposit allocation targets for all operators.
    /// @dev Target = totalCurrent * operatorWeight / totalWeight (in validator count).
    ///      Includes operators regardless of depositable capacity for informational purposes.
    ///      Actual allocation recalculates shares only across operators with usable capacity,
    ///      so real per-operator amounts may differ from the targets shown here.
    ///      Arrays are indexed by operator id; zero-weight operators have zero values.
    /// @return currentValidators Current active validator count per operator.
    /// @return targetValidators Target validator count per operator.
    function getDepositAllocationTargets()
        external
        view
        returns (uint256[] memory currentValidators, uint256[] memory targetValidators);

    /// @notice Returns current top-up allocation targets for all operators.
    /// @dev `target = totalCurrent * operatorWeight / totalWeight` (in wei).
    ///      Includes operators regardless of top-up capacity or whether allocation is enabled for informational purposes.
    ///      Actual allocation recalculates shares only across operators with allocation enabled and usable capacity,
    ///      so real per-operator amounts may differ from the targets shown here.
    ///      Arrays are indexed by operator id; zero-weight operators have zero values.
    /// @return currentAllocations Current operator stake in wei.
    /// @return targetAllocations Target operator stake in wei.
    function getTopUpAllocationTargets()
        external
        view
        returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations);

    /// @notice  Method to get list of operators and amount of Eth that can be topped up to operator from depositAmount
    /// @param depositAmount Amount of Eth that can be deposited to module
    function getDepositsAllocation(
        uint256 depositAmount
    ) external view returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations);

    /// @notice Returns current meta registry.
    function META_REGISTRY() external view returns (IMetaRegistry);
}
