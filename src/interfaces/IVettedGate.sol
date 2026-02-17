// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMerkleGate } from "./IMerkleGate.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "./IBaseModule.sol";
import { IAccounting } from "./IAccounting.sol";

interface IVettedGate is IMerkleGate {
    error InvalidCurveId();
    error ZeroModuleAddress();
    error NotAllowedToClaim();
    error NodeOperatorDoesNotExist();

    function MODULE() external view returns (IBaseModule);

    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Add a new Node Operator using ETH as bond.
    ///         At least one deposit data and corresponding bond should be provided.
    ///         msg.sender is marked as consumed and will not be able to create Node Operators
    ///         or claim the beneficial curve via this VettedGate instance.
    /// @param keysCount Signing keys count.
    /// @param publicKeys Public keys to submit.
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples.
    /// @param managementProperties Optional management properties for the Node Operator.
    /// @param proof Merkle proof of the sender being eligible to join via the gate.
    /// @param referrer Optional referrer address to pass through to module.
    /// @return nodeOperatorId Id of the created Node Operator.
    function addNodeOperatorETH(
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        NodeOperatorManagementProperties memory managementProperties,
        bytes32[] memory proof,
        address referrer
    ) external payable returns (uint256 nodeOperatorId);

    /// @notice Add a new Node Operator using stETH as bond.
    ///         At least one deposit data and corresponding bond should be provided.
    ///         msg.sender is marked as consumed and will not be able to create Node Operators
    ///         or claim the beneficial curve via this VettedGate instance.
    /// @notice Due to stETH rounding issue make sure to approve/sign permit with extra 10 wei to avoid revert.
    /// @param keysCount Signing keys count.
    /// @param publicKeys Public keys to submit.
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples.
    /// @param managementProperties Optional management properties for the Node Operator.
    /// @param permit Optional permit to use stETH as bond.
    /// @param proof Merkle proof of the sender being eligible to join via the gate.
    /// @param referrer Optional referrer address to pass through to module.
    /// @return nodeOperatorId Id of the created Node Operator.
    function addNodeOperatorStETH(
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        NodeOperatorManagementProperties memory managementProperties,
        IAccounting.PermitInput memory permit,
        bytes32[] memory proof,
        address referrer
    ) external returns (uint256 nodeOperatorId);

    /// @notice Add a new Node Operator using wstETH as bond.
    ///         At least one deposit data and corresponding bond should be provided.
    ///         msg.sender is marked as consumed and will not be able to create Node Operators
    ///         or claim the beneficial curve via this VettedGate instance.
    /// @notice Due to stETH rounding issue make sure to approve/sign permit with extra 10 wei to avoid revert.
    /// @param keysCount Signing keys count.
    /// @param publicKeys Public keys to submit.
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples.
    /// @param managementProperties Optional management properties for the Node Operator.
    /// @param permit Optional permit to use wstETH as bond.
    /// @param proof Merkle proof of the sender being eligible to join via the gate.
    /// @param referrer Optional referrer address to pass through to module.
    /// @return nodeOperatorId Id of the created Node Operator.
    function addNodeOperatorWstETH(
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        NodeOperatorManagementProperties memory managementProperties,
        IAccounting.PermitInput memory permit,
        bytes32[] memory proof,
        address referrer
    ) external returns (uint256 nodeOperatorId);

    /// @notice Claim the bond curve for an eligible Node Operator.
    ///         msg.sender is marked as consumed and will not be able to create Node Operators
    ///         or claim again via this VettedGate instance.
    /// @param nodeOperatorId Id of the Node Operator.
    /// @param proof Merkle proof of the sender being eligible to join via the gate.
    /// @dev Should be called by Node Operator owner.
    function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external;
}
