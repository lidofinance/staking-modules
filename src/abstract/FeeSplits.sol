// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { FeeSplitsLib } from "../lib/FeeSplitsLib.sol";

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

    uint256 public constant MAX_FEE_SPLITS = FeeSplitsLib.MAX_FEE_SPLITS;

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
    ) public view returns (SplitTransfer[] memory) {
        return FeeSplitsLib.getFeeSplitTransfers(_getFeeSplitsStorage(), nodeOperatorId, splittableShares);
    }

    /// @inheritdoc IFeeSplits
    function hasSplits(uint256 nodeOperatorId) public view returns (bool) {
        return _getFeeSplitsStorage().feeSplits[nodeOperatorId].length != 0;
    }

    function _updateFeeSplits(uint256 nodeOperatorId, FeeSplit[] calldata feeSplits, address stETH) internal {
        FeeSplitsLib.updateFeeSplits(_getFeeSplitsStorage(), nodeOperatorId, feeSplits, stETH);
    }

    function _increasePendingSharesToSplit(uint256 nodeOperatorId, uint256 shares) internal {
        FeeSplitsLib.increasePendingSharesToSplit(_getFeeSplitsStorage(), nodeOperatorId, shares);
    }

    /// @dev Transfer the pending shares to the fee split recipients, capped by the claimable amount
    /// @return transferredShares Shares sent to the recipients, to be deducted from the Node Operator's bond
    function _splitPendingShares(
        uint256 nodeOperatorId,
        uint256 claimableShares,
        address stETH
    ) internal returns (uint256 transferredShares) {
        return FeeSplitsLib.splitPendingShares(_getFeeSplitsStorage(), nodeOperatorId, claimableShares, stETH);
    }

    function _getFeeSplitsStorage() internal pure returns (FeeSplitsStorage storage $) {
        assembly ("memory-safe") {
            $.slot := FEE_SPLITS_STORAGE_LOCATION
        }
    }
}
