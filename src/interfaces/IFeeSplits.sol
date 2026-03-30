// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IFeeSplits {
    struct FeeSplit {
        address recipient;
        uint256 share; // in basis points
    }

    struct SplitTransfer {
        address recipient;
        uint256 shares;
    }

    event FeeSplitsSet(uint256 indexed nodeOperatorId, FeeSplit[] feeSplits);
    event PendingSharesToSplitChanged(uint256 indexed nodeOperatorId, uint256 pendingSharesToSplit);

    error PendingSharesExist();
    error FeeSplitsChangeWithUndistributedRewards();
    error TooManySplits();
    error TooManySplitShares();
    error ZeroSplitRecipient();
    error InvalidSplitRecipient();
    error ZeroSplitShare();

    /// @notice Get fee splits for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Array of FeeSplit structs defining recipients and their shares in basis points
    function getFeeSplits(uint256 nodeOperatorId) external view returns (FeeSplit[] memory);

    /// @notice Get the number of the pending shares to be split for the given Node Operator
    function getPendingSharesToSplit(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Check if the given Node Operator has fee splits
    function hasSplits(uint256 nodeOperatorId) external view returns (bool);

    /// @notice Calculate fee split transfers for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param splittableShares Shares amount that can be split according to the current state of the Node Operator rewards and pending shares to split
    ///                         getPendingSharesToSplit() + FeeDistributor.getFeesToDistribute()
    /// @return transfers Shares amounts to transfer to each split recipient
    function getFeeSplitTransfers(
        uint256 nodeOperatorId,
        uint256 splittableShares
    ) external view returns (SplitTransfer[] memory transfers);
}
