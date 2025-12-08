// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IBondCurve {
    /// @dev Bond curve structure.
    ///
    /// It contains:
    ///  - intervals    |> intervals-based representation of the bond curve
    ///
    /// The interval is defined by:
    ///  - minKeysCount |> minimum keys count (inclusive) of the interval
    ///  - minBond      |> minimum bond amount (inclusive) of the interval
    ///  - trend        |> trend of the bond amount in the interval
    ///
    /// For example, how the curve intervals look like:
    ///   Interval 0: minKeysCount = 1, minBond = 2 ETH, trend = 2 ETH
    ///   Interval 1: minKeysCount = 2, minBond = 3.9 ETH, trend = 1.9 ETH
    ///   Interval 2: minKeysCount = 3, minBond = 5.7 ETH, trend = 1.8 ETH
    ///
    ///   Bond Amount (ETH)
    ///       ^
    ///       |
    ///     6 -
    ///       | ------------------ 5.7 ETH --> .
    ///   5.5 -                              ..^
    ///       |                             .  |
    ///     5 -                            .   |
    ///       |                           .    |
    ///   4.5 -                          .     |
    ///       |                         .      |
    ///     4 -                       ..       |
    ///       | ------- 3.9 ETH --> ..         |
    ///   3.5 -                    .^          |
    ///       |                  .. |          |
    ///     3 -                ..   |          |
    ///       |               .     |          |
    ///   2.5 -              .      |          |
    ///       |            ..       |          |
    ///     2 - -------->..         |          |
    ///       |          ^          |          |
    ///       |----------|----------|----------|----------|----> Keys Count
    ///       |          1          2          3          i
    ///
    struct BondCurveData {
        BondCurveInterval[] intervals;
    }

    struct BondCurveInterval {
        uint256 minKeysCount;
        uint256 minBond;
        uint256 trend;
    }

    struct BondCurveIntervalInput {
        uint256 minKeysCount;
        uint256 trend;
    }

    event BondCurveAdded(
        uint256 indexed curveId,
        BondCurveIntervalInput[] bondCurveIntervals
    );
    event BondCurveUpdated(
        uint256 indexed curveId,
        BondCurveIntervalInput[] bondCurveIntervals
    );
    event BondCurveSet(uint256 indexed nodeOperatorId, uint256 curveId);

    error InvalidBondCurveLength();
    error InvalidBondCurveValues();
    error InvalidBondCurveId();
    error InvalidInitializationCurveId();

    function DEFAULT_BOND_CURVE_ID() external view returns (uint256);

    /// @notice Get the number of available curves
    /// @return Number of available curves
    function getCurvesCount() external view returns (uint256);

    /// @notice Return bond curve for the given curve id
    /// @param curveId Curve id to get bond curve for
    /// @return Bond curve
    /// @dev Reverts if `curveId` is invalid
    function getCurveInfo(
        uint256 curveId
    ) external view returns (BondCurveData memory);

    /// @notice Get bond curve for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond curve
    function getBondCurve(
        uint256 nodeOperatorId
    ) external view returns (BondCurveData memory);

    /// @notice Get bond curve ID for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond curve ID
    function getBondCurveId(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get required bond in ETH for the given number of keys for default bond curve
    /// @dev To calculate the amount for the new keys 2 calls are required:
    ///      getBondAmountByKeysCount(newTotal) - getBondAmountByKeysCount(currentTotal)
    /// @param keys Number of keys to get required bond for
    /// @param curveId Id of the curve to perform calculations against
    /// @return Amount for particular keys count
    function getBondAmountByKeysCount(
        uint256 keys,
        uint256 curveId
    ) external view returns (uint256);

    /// @notice Get keys count for the given bond amount with default bond curve
    /// @param amount Bond amount in ETH (stETH)to get keys count for
    /// @param curveId Id of the curve to perform calculations against
    /// @return Keys count
    function getKeysCountByBondAmount(
        uint256 amount,
        uint256 curveId
    ) external view returns (uint256);
}
