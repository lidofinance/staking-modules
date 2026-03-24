// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { NodeOperator, IBaseModule } from "../interfaces/IBaseModule.sol";

library NOAddresses {
    /// @notice Propose a new manager address for the Node Operator.
    /// @dev Passing address(0) clears the pending proposal without changing the current manager address.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed manager address, or address(0) to cancel the current proposal
    function proposeNodeOperatorManagerAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address managerAddress = no.managerAddress;

        if (managerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (managerAddress != msg.sender) revert IBaseModule.SenderIsNotManagerAddress();
        if (managerAddress == proposedAddress) revert IBaseModule.SameAddress();

        address oldProposedAddress = no.proposedManagerAddress;

        if (oldProposedAddress == proposedAddress) revert IBaseModule.AlreadyProposed();

        no.proposedManagerAddress = proposedAddress;

        emit IBaseModule.NodeOperatorManagerAddressChangeProposed(nodeOperatorId, oldProposedAddress, proposedAddress);
    }

    /// @notice Confirm a new manager address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorManagerAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address oldManagerAddress = no.managerAddress;

        if (oldManagerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (no.proposedManagerAddress != msg.sender) revert IBaseModule.SenderIsNotProposedAddress();

        no.managerAddress = msg.sender;
        delete no.proposedManagerAddress;

        emit IBaseModule.NodeOperatorManagerAddressChanged(nodeOperatorId, oldManagerAddress, msg.sender);
    }

    /// @notice Propose a new reward address for the Node Operator.
    /// @dev Passing address(0) clears the pending proposal without changing the current reward address.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed reward address, or address(0) to cancel the current proposal
    function proposeNodeOperatorRewardAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address rewardAddress = no.rewardAddress;

        if (rewardAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (rewardAddress != msg.sender) revert IBaseModule.SenderIsNotRewardAddress();
        if (rewardAddress == proposedAddress) revert IBaseModule.SameAddress();

        address oldProposedAddress = no.proposedRewardAddress;

        if (oldProposedAddress == proposedAddress) revert IBaseModule.AlreadyProposed();

        no.proposedRewardAddress = proposedAddress;

        emit IBaseModule.NodeOperatorRewardAddressChangeProposed(nodeOperatorId, oldProposedAddress, proposedAddress);
    }

    /// @notice Confirm a new reward address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorRewardAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address oldRewardAddress = no.rewardAddress;

        if (oldRewardAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (no.proposedRewardAddress != msg.sender) revert IBaseModule.SenderIsNotProposedAddress();

        no.rewardAddress = msg.sender;
        delete no.proposedRewardAddress;

        emit IBaseModule.NodeOperatorRewardAddressChanged(nodeOperatorId, oldRewardAddress, msg.sender);
    }

    /// @notice Reset the manager address to the reward address.
    ///         Should be called from the reward address
    /// @param nodeOperatorId ID of the Node Operator
    function resetNodeOperatorManagerAddress(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address rewardAddress = no.rewardAddress;

        if (rewardAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (no.extendedManagerPermissions) revert IBaseModule.MethodCallIsNotAllowed();
        if (rewardAddress != msg.sender) revert IBaseModule.SenderIsNotRewardAddress();

        address previousManagerAddress = no.managerAddress;

        if (previousManagerAddress == rewardAddress) revert IBaseModule.SameAddress();

        no.managerAddress = rewardAddress;
        // @dev Gas golfing
        if (no.proposedManagerAddress != address(0)) delete no.proposedManagerAddress;

        emit IBaseModule.NodeOperatorManagerAddressChanged(nodeOperatorId, previousManagerAddress, rewardAddress);
    }

    /// @notice Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator.
    ///         Should be called from the current manager address
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newAddress New reward address
    function changeNodeOperatorRewardAddress(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address newAddress,
        address stETH
    ) external {
        if (newAddress == address(0)) revert IBaseModule.ZeroRewardAddress();
        if (newAddress == stETH) revert IBaseModule.InvalidRewardAddress();

        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address oldRewardAddress = no.rewardAddress;

        if (oldRewardAddress == newAddress) revert IBaseModule.SameAddress();

        address managerAddress = no.managerAddress;

        if (managerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (!no.extendedManagerPermissions) revert IBaseModule.MethodCallIsNotAllowed();
        if (managerAddress != msg.sender) revert IBaseModule.SenderIsNotManagerAddress();

        no.rewardAddress = newAddress;
        // @dev Gas golfing
        if (no.proposedRewardAddress != address(0)) delete no.proposedRewardAddress;

        emit IBaseModule.NodeOperatorRewardAddressChanged(nodeOperatorId, oldRewardAddress, newAddress);
    }

    /// @notice Change both reward and manager addresses of a node operator.
    /// @dev XXX: Use with caution! No check of the caller.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newManagerAddress New manager address
    /// @param newRewardAddress New reward address
    function changeNodeOperatorAddresses(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress,
        address stETH
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];

        address oldManagerAddress = no.managerAddress;
        address oldRewardAddress = no.rewardAddress;

        if (oldManagerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (newManagerAddress == address(0)) revert IBaseModule.ZeroManagerAddress();
        if (newRewardAddress == address(0)) revert IBaseModule.ZeroRewardAddress();
        if (newManagerAddress == stETH) revert IBaseModule.InvalidManagerAddress();
        if (newRewardAddress == stETH) revert IBaseModule.InvalidRewardAddress();

        bool isSameManagerAddress = newManagerAddress == oldManagerAddress;
        bool isSameRewardAddress = newRewardAddress == oldRewardAddress;

        if (!isSameManagerAddress) {
            no.managerAddress = newManagerAddress;
            if (no.proposedManagerAddress != address(0)) delete no.proposedManagerAddress;

            emit IBaseModule.NodeOperatorManagerAddressChanged(nodeOperatorId, oldManagerAddress, newManagerAddress);
        }
        if (!isSameRewardAddress) {
            no.rewardAddress = newRewardAddress;
            if (no.proposedRewardAddress != address(0)) delete no.proposedRewardAddress;

            emit IBaseModule.NodeOperatorRewardAddressChanged(nodeOperatorId, oldRewardAddress, newRewardAddress);
        }
    }
}
