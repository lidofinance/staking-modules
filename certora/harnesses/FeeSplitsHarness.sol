// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { FeeSplits } from "../../src/abstract/FeeSplits.sol";

/// @notice Exposes the production FeeSplits transitions for isolated verification.
/// @dev This harness deliberately omits Accounting's authorization, reward pulling,
///      bond accounting, and token transfers. It verifies only FeeSplits mechanics.
contract FeeSplitsHarness is FeeSplits {
    /// @notice Invoke the production split configuration transition.
    function updateSplits(uint256 id, FeeSplit[] calldata splits, address stETH) external {
        _updateFeeSplits(id, splits, stETH);
    }

    /// @notice Invoke the production pending-share credit transition.
    function increasePending(uint256 id, uint256 shares) external {
        _increasePendingSharesToSplit(id, shares);
    }

    /// @notice Invoke the production pending-share debit transition.
    function decreasePending(uint256 id, uint256 shares) external {
        _unsafeDecreasePendingSharesToSplit(id, shares);
    }

    /// @notice Number of configured recipients, without copying the array.
    function splitCount(uint256 id) external view returns (uint256) {
        return _getFeeSplitsStorage().feeSplits[id].length;
    }

    /// @notice Inspect a configured entry without abstracting production storage.
    function splitAt(uint256 id, uint256 index) external view returns (address recipient, uint256 share) {
        FeeSplit storage split = _getFeeSplitsStorage().feeSplits[id][index];
        return (split.recipient, split.share);
    }

    /// @notice Sum configured basis points for the specification's budget checks.
    function splitShareSum(uint256 id) external view returns (uint256 sum) {
        FeeSplit[] storage splits = _getFeeSplitsStorage().feeSplits[id];
        for (uint256 i; i < splits.length; ++i) sum += splits[i].share;
    }

    /// @notice Number of transfers returned by the real payout calculation.
    function transferCount(uint256 id, uint256 amount) external view returns (uint256) {
        return getFeeSplitTransfers(id, amount).length;
    }

    /// @notice Inspect a transfer returned by the real payout calculation.
    function transferAt(
        uint256 id,
        uint256 amount,
        uint256 index
    ) external view returns (address recipient, uint256 shares) {
        SplitTransfer[] memory transfers = getFeeSplitTransfers(id, amount);
        return (transfers[index].recipient, transfers[index].shares);
    }

    /// @notice Sum the actual calculated transfers; this is an observation only.
    function transferSum(uint256 id, uint256 amount) external view returns (uint256 sum) {
        SplitTransfer[] memory transfers = getFeeSplitTransfers(id, amount);
        for (uint256 i; i < transfers.length; ++i) sum += transfers[i].shares;
    }
}
