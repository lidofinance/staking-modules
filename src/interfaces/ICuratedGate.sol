// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IMerkleGate } from "./IMerkleGate.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IOperatorsData } from "./IOperatorsData.sol";
import { IAccounting } from "./IAccounting.sol";

/// @title Curated Gate Interface
/// @notice Allows eligible addresses to create Node Operators and store metadata.
interface ICuratedGate is IMerkleGate {
    /// Errors
    error InvalidCurveId();
    error ZeroModuleAddress();
    error ZeroModuleId();
    error ZeroOperatorsDataAddress();
    error ZeroAdminAddress();

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    /// @return MODULE Curated module reference
    function MODULE() external view returns (ICuratedModule);

    /// @return MODULE_ID Curated module id cached for OperatorsData integration
    function MODULE_ID() external view returns (uint256);

    /// @return ACCOUNTING Accounting reference
    function ACCOUNTING() external view returns (IAccounting);

    /// @return OPERATORS_DATA Operators metadata storage reference
    function OPERATORS_DATA() external view returns (IOperatorsData);

    /// @return curveId Instance-specific custom curve id
    function curveId() external view returns (uint256);

    /// @notice Pause the gate for a given duration
    /// @param duration Duration in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Resume the gate
    function resume() external;

    /// @notice Create an empty Node Operator for the caller if eligible.
    ///         Stores provided name/description in OperatorsData. Marks caller as consumed.
    /// @param name Display name of the Node Operator
    /// @param description Description of the Node Operator
    /// @param managerAddress Address to set as manager; if zero, defaults will be used by the module
    /// @param rewardAddress Address to set as rewards receiver; if zero, defaults will be used by the module
    /// @param proof Merkle proof for the caller address
    /// @return nodeOperatorId Newly created Node Operator id
    function createNodeOperator(
        string calldata name,
        string calldata description,
        address managerAddress,
        address rewardAddress,
        bytes32[] calldata proof
    ) external returns (uint256 nodeOperatorId);
}
