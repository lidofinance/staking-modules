// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IBondLock {
    /// @dev Bond lock structure.
    /// It contains:
    ///  - amount   |> amount of locked bond
    ///  - until    |> timestamp until locked bond is retained
    struct BondLockData {
        uint128 amount;
        uint128 until;
    }

    event BondLockChanged(uint256 indexed nodeOperatorId, uint256 newAmount, uint256 until);
    event BondLockRemoved(uint256 indexed nodeOperatorId);
    event ExpiredBondLockRemoved(uint256 indexed nodeOperatorId);

    event BondLockPeriodChanged(uint256 period);

    error InvalidBondLockPeriod();
    error InvalidBondLockAmount();
    error BondLockNotExpired();
    error NoBondLocked();

    function MIN_BOND_LOCK_PERIOD() external view returns (uint256);

    function MAX_BOND_LOCK_PERIOD() external view returns (uint256);

    /// @notice Get default bond lock period
    /// @return period Default bond lock period
    function getBondLockPeriod() external view returns (uint256 period);

    /// @notice Get information about the locked bond for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Locked bond info
    function getLockedBondInfo(uint256 nodeOperatorId) external view returns (BondLockData memory);

    /// @notice Get amount of the locked bond in ETH (stETH) by the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Amount of the actual locked bond
    function getLockedBond(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Check if the bond lock for the given Node Operator has expired
    /// @param nodeOperatorId ID of the Node Operator
    /// @return True if the bond lock has expired or there is no lock, false otherwise
    function isLockExpired(uint256 nodeOperatorId) external view returns (bool);
}
