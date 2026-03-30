// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { IFeeSplits } from "../interfaces/IFeeSplits.sol";

/// @dev Fee split mechanics abstract contract
///
/// It gives the ability to:
///  - set fee split recipients and shares for Node Operators
///  - split rewards between recipients and keep the remainder on the bond
///  - track pending shares waiting to be split
///
/// Internal non-view methods should be used in the Module contract with
/// additional requirements (if any).
abstract contract FeeSplits is IFeeSplits {
    /// @custom:storage-location erc7201:FeeSplits
    struct FeeSplitsStorage {
        mapping(uint256 nodeOperatorId => FeeSplit[]) feeSplits;
        // NOTE: Contains operator's and splits recipients' shares. May accumulate over time.
        mapping(uint256 nodeOperatorId => uint256 pendingToSplit) pendingSharesToSplit;
    }

    // keccak256(abi.encode(uint256(keccak256("FeeSplits")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEE_SPLITS_STORAGE_LOCATION =
        0xac5584dcb35bfb1b3f4187762b10cb284ff937e63b5eb675e2e8e8876c7ee000;

    uint256 internal constant MAX_BP = 10_000;
    uint256 public constant MAX_FEE_SPLITS = 10;

    /// @inheritdoc IFeeSplits
    function getFeeSplits(uint256 nodeOperatorId) external view returns (FeeSplit[] memory) {
        return _getFeeSplitsStorage().feeSplits[nodeOperatorId];
    }

    /// @inheritdoc IFeeSplits
    function getPendingSharesToSplit(uint256 nodeOperatorId) public view returns (uint256) {
        return _getFeeSplitsStorage().pendingSharesToSplit[nodeOperatorId];
    }

    /// @inheritdoc IFeeSplits
    function getFeeSplitTransfers(
        uint256 nodeOperatorId,
        uint256 splittableShares
    ) public view returns (SplitTransfer[] memory transfers) {
        if (splittableShares == 0) return transfers;
        FeeSplitsStorage storage $ = _getFeeSplitsStorage();
        FeeSplit[] storage splits = $.feeSplits[nodeOperatorId];
        transfers = new SplitTransfer[](splits.length);
        for (uint256 i; i < splits.length; ++i) {
            FeeSplit storage feeSplit = splits[i];
            // NOTE: Due to rounding error, shares left for the node operator might contain some dust.
            uint256 amount = (splittableShares * feeSplit.share) / MAX_BP;
            transfers[i] = SplitTransfer({ recipient: feeSplit.recipient, shares: amount });
        }
    }

    /// @inheritdoc IFeeSplits
    function hasSplits(uint256 nodeOperatorId) public view returns (bool) {
        return _getFeeSplitsStorage().feeSplits[nodeOperatorId].length != 0;
    }

    function _updateFeeSplits(uint256 nodeOperatorId, FeeSplit[] calldata feeSplits, address stETH) internal {
        FeeSplitsStorage storage $ = _getFeeSplitsStorage();
        if ($.pendingSharesToSplit[nodeOperatorId] > 0) revert PendingSharesExist();

        uint256 len = _validateFeeSplits(feeSplits, stETH);

        FeeSplit[] storage dst = $.feeSplits[nodeOperatorId];
        delete $.feeSplits[nodeOperatorId];
        for (uint256 i; i < len; ++i) {
            dst.push(feeSplits[i]);
        }

        emit FeeSplitsSet(nodeOperatorId, feeSplits);
    }

    function _increasePendingSharesToSplit(uint256 nodeOperatorId, uint256 shares) internal {
        if (shares == 0) return;
        FeeSplitsStorage storage $ = _getFeeSplitsStorage();
        uint256 newPendingSharesToSplit = $.pendingSharesToSplit[nodeOperatorId] + shares;
        $.pendingSharesToSplit[nodeOperatorId] = newPendingSharesToSplit;
        emit PendingSharesToSplitChanged(nodeOperatorId, newPendingSharesToSplit);
    }

    function _decreasePendingSharesToSplit(uint256 nodeOperatorId, uint256 shares) internal {
        if (shares == 0) return;
        FeeSplitsStorage storage $ = _getFeeSplitsStorage();
        uint256 current = $.pendingSharesToSplit[nodeOperatorId];
        shares = shares > current ? current : shares;
        uint256 newPendingSharesToSplit = current - (shares);
        $.pendingSharesToSplit[nodeOperatorId] = newPendingSharesToSplit;
        emit PendingSharesToSplitChanged(nodeOperatorId, newPendingSharesToSplit);
    }

    function _getFeeSplitsStorage() internal pure returns (FeeSplitsStorage storage $) {
        assembly {
            $.slot := FEE_SPLITS_STORAGE_LOCATION
        }
    }

    function _validateFeeSplits(FeeSplit[] calldata feeSplits, address stETH) private pure returns (uint256 len) {
        len = feeSplits.length;
        if (len > MAX_FEE_SPLITS) revert TooManySplits();

        uint256 totalShare;
        for (uint256 i; i < len; ++i) {
            FeeSplit calldata fs = feeSplits[i];
            if (fs.recipient == address(0)) revert ZeroSplitRecipient();
            if (fs.recipient == stETH) revert InvalidSplitRecipient();
            if (fs.share == 0) revert ZeroSplitShare();
            totalShare += fs.share;
        }

        // totalShare might be lower than MAX_BP. The remainder goes to the
        // Node Operator's bond.
        if (totalShare > MAX_BP) revert TooManySplitShares();
    }
}
