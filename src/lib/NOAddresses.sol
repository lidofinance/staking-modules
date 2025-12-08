// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { NodeOperator, IBaseModule } from "../interfaces/IBaseModule.sol";

/// Library for changing and reset node operator's manager and reward addresses
/// @dev the only use of this to be a library is to save CSModule contract size via delegatecalls
interface INOAddresses {
    event NodeOperatorManagerAddressChangeProposed(
        uint256 indexed nodeOperatorId,
        address indexed oldProposedAddress,
        address indexed newProposedAddress
    );
    event NodeOperatorRewardAddressChangeProposed(
        uint256 indexed nodeOperatorId,
        address indexed oldProposedAddress,
        address indexed newProposedAddress
    );
    // args order as in https://github.com/OpenZeppelin/openzeppelin-contracts/blob/11dc5e3809ebe07d5405fe524385cbe4f890a08b/contracts/access/Ownable.sol#L33
    event NodeOperatorManagerAddressChanged(
        uint256 indexed nodeOperatorId,
        address indexed oldAddress,
        address indexed newAddress
    );
    // args order as in https://github.com/OpenZeppelin/openzeppelin-contracts/blob/11dc5e3809ebe07d5405fe524385cbe4f890a08b/contracts/access/Ownable.sol#L33
    event NodeOperatorRewardAddressChanged(
        uint256 indexed nodeOperatorId,
        address indexed oldAddress,
        address indexed newAddress
    );

    error AlreadyProposed();
    error SameAddress();
    error SenderIsNotManagerAddress();
    error SenderIsNotRewardAddress();
    error SenderIsNotProposedAddress();
    error MethodCallIsNotAllowed();
    error ZeroManagerAddress();
    error ZeroRewardAddress();
}

library NOAddresses {
    /// @notice Propose a new manager address for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed manager address
    function proposeNodeOperatorManagerAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address managerAddress = no.managerAddress;

        if (managerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (managerAddress != msg.sender) {
            revert INOAddresses.SenderIsNotManagerAddress();
        }

        if (managerAddress == proposedAddress) {
            revert INOAddresses.SameAddress();
        }

        address oldProposedAddress = no.proposedManagerAddress;

        if (oldProposedAddress == proposedAddress) {
            revert INOAddresses.AlreadyProposed();
        }

        no.proposedManagerAddress = proposedAddress;

        emit INOAddresses.NodeOperatorManagerAddressChangeProposed(
            nodeOperatorId,
            oldProposedAddress,
            proposedAddress
        );
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

        if (oldManagerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (no.proposedManagerAddress != msg.sender) {
            revert INOAddresses.SenderIsNotProposedAddress();
        }

        no.managerAddress = msg.sender;
        delete no.proposedManagerAddress;

        emit INOAddresses.NodeOperatorManagerAddressChanged(
            nodeOperatorId,
            oldManagerAddress,
            msg.sender
        );
    }

    /// @notice Propose a new reward address for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed reward address
    function proposeNodeOperatorRewardAddressChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address rewardAddress = no.rewardAddress;

        if (rewardAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (rewardAddress != msg.sender) {
            revert INOAddresses.SenderIsNotRewardAddress();
        }

        if (rewardAddress == proposedAddress) {
            revert INOAddresses.SameAddress();
        }

        address oldProposedAddress = no.proposedRewardAddress;

        if (oldProposedAddress == proposedAddress) {
            revert INOAddresses.AlreadyProposed();
        }

        no.proposedRewardAddress = proposedAddress;

        emit INOAddresses.NodeOperatorRewardAddressChangeProposed(
            nodeOperatorId,
            oldProposedAddress,
            proposedAddress
        );
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

        if (oldRewardAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (no.proposedRewardAddress != msg.sender) {
            revert INOAddresses.SenderIsNotProposedAddress();
        }

        no.rewardAddress = msg.sender;
        delete no.proposedRewardAddress;

        emit INOAddresses.NodeOperatorRewardAddressChanged(
            nodeOperatorId,
            oldRewardAddress,
            msg.sender
        );
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

        if (rewardAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (no.extendedManagerPermissions) {
            revert INOAddresses.MethodCallIsNotAllowed();
        }

        if (rewardAddress != msg.sender) {
            revert INOAddresses.SenderIsNotRewardAddress();
        }

        address previousManagerAddress = no.managerAddress;

        if (previousManagerAddress == rewardAddress) {
            revert INOAddresses.SameAddress();
        }

        no.managerAddress = rewardAddress;
        // @dev Gas golfing
        if (no.proposedManagerAddress != address(0)) {
            delete no.proposedManagerAddress;
        }

        emit INOAddresses.NodeOperatorManagerAddressChanged(
            nodeOperatorId,
            previousManagerAddress,
            rewardAddress
        );
    }

    /// @notice Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator.
    ///         Should be called from the current manager address
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newAddress New reward address
    function changeNodeOperatorRewardAddress(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address newAddress
    ) external {
        if (newAddress == address(0)) {
            revert INOAddresses.ZeroRewardAddress();
        }

        NodeOperator storage no = nodeOperators[nodeOperatorId];
        address oldRewardAddress = no.rewardAddress;

        if (oldRewardAddress == newAddress) {
            revert INOAddresses.SameAddress();
        }

        address managerAddress = no.managerAddress;

        if (managerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (!no.extendedManagerPermissions) {
            revert INOAddresses.MethodCallIsNotAllowed();
        }

        if (managerAddress != msg.sender) {
            revert INOAddresses.SenderIsNotManagerAddress();
        }

        no.rewardAddress = newAddress;
        // @dev Gas golfing
        if (no.proposedRewardAddress != address(0)) {
            delete no.proposedRewardAddress;
        }

        emit INOAddresses.NodeOperatorRewardAddressChanged(
            nodeOperatorId,
            oldRewardAddress,
            newAddress
        );
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
        address newRewardAddress
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];

        address oldManagerAddress = no.managerAddress;
        address oldRewardAddress = no.rewardAddress;

        if (oldManagerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (newManagerAddress == address(0)) {
            revert INOAddresses.ZeroManagerAddress();
        }
        if (newRewardAddress == address(0)) {
            revert INOAddresses.ZeroRewardAddress();
        }

        bool isSameManagerAddress = newManagerAddress == oldManagerAddress;
        bool isSameRewardAddress = newRewardAddress == oldRewardAddress;

        if (isSameManagerAddress && isSameRewardAddress) {
            revert INOAddresses.SameAddress();
        }

        if (!isSameManagerAddress) {
            no.managerAddress = newManagerAddress;

            emit INOAddresses.NodeOperatorManagerAddressChanged(
                nodeOperatorId,
                oldManagerAddress,
                newManagerAddress
            );
        }

        if (!isSameRewardAddress) {
            no.rewardAddress = newRewardAddress;

            emit INOAddresses.NodeOperatorRewardAddressChanged(
                nodeOperatorId,
                oldRewardAddress,
                newRewardAddress
            );
        }
    }
}
