// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "./IBaseModule.sol";
import { IStakingModuleV2 } from "./IStakingModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";

interface ICuratedModule is IBaseModule, IStakingModuleV2 {
    event NodeOperatorBalanceUpdated(
        uint256 indexed operatorId,
        uint256 balanceWei
    );
    event NodeOperatorWeightsUpToDate();

    error ZeroMetaRegistryAddress();
    error SenderIsNotMetaRegistry();
    error InvalidMaxCount();
    error NodeOperatorWeightsUpdateInProgress();

    /// @notice Initializes the contract.
    /// @param admin An address to grant the DEFAULT_ADMIN_ROLE to.
    function initialize(address admin) external;

    /// @notice Change both reward and manager addresses of a node operator.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newManagerAddress New manager address
    /// @param newRewardAddress New reward address
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external;

    /// @notice Notifies the module about the weight change of a node operator.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newWeight The new weight of the node operator.
    function onNodeOperatorWeightChange(
        uint256 nodeOperatorId,
        uint256 newWeight
    ) external;

    /// @notice Request refreshing node operator weights for all operators.
    function requestFullOperatorWeightsUpdate() external;

    /// @notice Process node operator weight updates in order.
    /// @param maxCount Maximum operators to process in this call.
    /// @return operatorsLeft Number of operators left to process.
    function batchUpdateNodeOperatorWeights(
        uint256 maxCount
    ) external returns (uint256 operatorsLeft);

    /// @notice Returns the count of node operators left to update weights for.
    function getNodeOperatorWeightsToUpdateCount()
        external
        view
        returns (uint256);

    /// @notice Returns stored operator balance (validators + pending).
    /// @param operatorId ID of the Node Operator
    function getNodeOperatorBalance(
        uint256 operatorId
    ) external view returns (uint256);

    /// @notice Returns operator weights used for operator-level allocations in the module.
    /// @dev Provides weights from the on-chain allocation strategy used by the module.
    /// @param operatorIds Node operator IDs to query.
    /// @return operatorWeights Weights aligned with operatorIds.
    function getOperatorWeights(
        uint256[] calldata operatorIds
    ) external view returns (uint256[] memory operatorWeights);

    /// @notice  Method to get list of operators and amount of Eth that can be topped up to operator from depositAmount
    /// @param depositAmount Amount of Eth that can be deposited to module
    function getDepositsAllocation(
        uint256 depositAmount
    )
        external
        view
        returns (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        );

    function OPERATOR_ADDRESSES_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Returns current meta registry.
    function META_REGISTRY() external view returns (IMetaRegistry);
}
