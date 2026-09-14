// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseWeightBoostProvider } from "./IBaseWeightBoostProvider.sol";

/// @dev A point of a monotonically increasing step function, packed into one storage slot. At an input
///      greater than or equal to `threshold`, `value` applies until the next threshold is reached.
struct Step {
    uint128 threshold;
    uint128 value;
}

/// @notice A governance-configurable monotonically increasing step function.
/// @dev Thresholds and values must each be strictly increasing. Before the first threshold the function
///      returns zero; at and after a threshold it returns that step's value; after the final threshold the
///      final value continues to apply. Provider-specific validation may impose additional bounds or forbid
///      a zero threshold or value.
interface IStepwiseWeightBoost is IBaseWeightBoostProvider {
    event StepsSet(Step[] steps);

    error InvalidStepCount();
    error InvalidStep(uint256 index);
    error UnorderedSteps(uint256 index);

    /// @notice Replace the complete step function and request a provider-wide weight refresh.
    /// @dev The caller must have DEFAULT_ADMIN_ROLE. MetaRegistry is notified after the new steps are stored.
    function setSteps(Step[] calldata steps) external;

    /// @notice Returns the complete configured step function in ascending threshold order.
    function getSteps() external view returns (Step[] memory);

    /// @notice Maximum number of configured steps.
    function MAX_STEPS() external view returns (uint256);

    /// @notice Capability-wide ceiling for a step value.
    /// @dev A provider with a narrower domain may reject values below this ceiling through its own
    ///      step validation; see the provider interface for its effective bound.
    function MAX_STEP_VALUE() external view returns (uint256);
}
