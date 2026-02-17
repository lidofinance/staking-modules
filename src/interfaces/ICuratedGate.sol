// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMerkleGate } from "./IMerkleGate.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";
import { IAccounting } from "./IAccounting.sol";

/// @title Curated Gate Interface
/// @notice Allows eligible addresses to create Node Operators and store metadata.
interface ICuratedGate is IMerkleGate {
    /// Errors
    error InvalidCurveId();
    error ZeroModuleAddress();

    /// @return MODULE Curated module reference
    function MODULE() external view returns (ICuratedModule);

    /// @return ACCOUNTING Accounting reference
    function ACCOUNTING() external view returns (IAccounting);

    /// @return META_REGISTRY Operators metadata registry reference
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice Create an empty Node Operator for the caller if eligible.
    ///         Stores provided name/description in MetaRegistry. Marks caller as consumed.
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
