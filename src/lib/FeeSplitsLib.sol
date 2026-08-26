// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { IFeeSplits } from "../interfaces/IFeeSplits.sol";
import { ILido } from "../interfaces/ILido.sol";
import { FeeSplits } from "../abstract/FeeSplits.sol";
import { MAX_BP } from "../lib/Constants.sol";

/// Library for managing fee splits
/// @dev External deployment-linked library used by Accounting.
library FeeSplitsLib {
    /// @dev Exposed to the integrations via the `FeeSplits.MAX_FEE_SPLITS` getter
    uint256 internal constant MAX_FEE_SPLITS = 10;

    /// @dev Set the fee split recipients and shares for the Node Operator
    function updateFeeSplits(
        FeeSplits.FeeSplitsStorage storage feeSplitsStorage,
        uint256 nodeOperatorId,
        IFeeSplits.FeeSplit[] calldata feeSplits,
        address stETH
    ) external {
        if (feeSplitsStorage.pendingSharesToSplit[nodeOperatorId] > 0) revert IFeeSplits.PendingSharesExist();

        uint256 len = _check(feeSplits, stETH);

        IFeeSplits.FeeSplit[] storage dst = feeSplitsStorage.feeSplits[nodeOperatorId];
        delete feeSplitsStorage.feeSplits[nodeOperatorId];
        for (uint256 i; i < len; ++i) {
            dst.push(feeSplits[i]);
        }

        emit IFeeSplits.FeeSplitsSet(nodeOperatorId, feeSplits);
    }

    /// @dev Increase the shares awaiting to be split
    function increasePendingSharesToSplit(
        FeeSplits.FeeSplitsStorage storage feeSplitsStorage,
        uint256 nodeOperatorId,
        uint256 shares
    ) external {
        if (shares == 0) return;

        uint256 pendingToSplit = feeSplitsStorage.pendingSharesToSplit[nodeOperatorId] + shares;
        feeSplitsStorage.pendingSharesToSplit[nodeOperatorId] = pendingToSplit;
        emit IFeeSplits.PendingSharesToSplitChanged(nodeOperatorId, pendingToSplit);
    }

    /// @dev Transfer the pending shares to the fee split recipients, capped by the claimable amount
    /// @return transferredShares Shares sent to the recipients, to be deducted from the Node Operator's bond
    function splitPendingShares(
        FeeSplits.FeeSplitsStorage storage feeSplitsStorage,
        uint256 nodeOperatorId,
        uint256 claimableShares,
        address stETH
    ) external returns (uint256 transferredShares) {
        uint256 pendingToSplit = feeSplitsStorage.pendingSharesToSplit[nodeOperatorId];
        if (pendingToSplit == 0) return 0;

        uint256 splittableShares = claimableShares > pendingToSplit ? pendingToSplit : claimableShares;
        IFeeSplits.SplitTransfer[] memory transfers = getFeeSplitTransfers(
            feeSplitsStorage,
            nodeOperatorId,
            splittableShares
        );
        for (uint256 i; i < transfers.length; ++i) {
            uint256 shares = transfers[i].shares;
            if (shares != 0) {
                ILido(stETH).transferShares(transfers[i].recipient, shares);
                transferredShares += shares;
            }
        }

        // NOTE: `splittableShares` is the whole split operation base. It includes
        //       the Node Operator's retained shares (split remainder), so we
        //       must decrease pending by the base, not by transferred shares sum.
        unchecked {
            pendingToSplit -= splittableShares;
        }
        feeSplitsStorage.pendingSharesToSplit[nodeOperatorId] = pendingToSplit;
        emit IFeeSplits.PendingSharesToSplitChanged(nodeOperatorId, pendingToSplit);
    }

    function getFeeSplitTransfers(
        FeeSplits.FeeSplitsStorage storage feeSplitsStorage,
        uint256 nodeOperatorId,
        uint256 splittableShares
    ) public view returns (IFeeSplits.SplitTransfer[] memory transfers) {
        if (splittableShares == 0) return transfers;

        IFeeSplits.FeeSplit[] storage splits = feeSplitsStorage.feeSplits[nodeOperatorId];
        uint256 splitsCount = splits.length;
        transfers = new IFeeSplits.SplitTransfer[](splitsCount);
        for (uint256 i; i < splitsCount; ++i) {
            IFeeSplits.FeeSplit storage feeSplit = splits[i];
            // NOTE: Due to rounding error, shares left for the node operator might contain some dust.
            uint256 amount = (splittableShares * feeSplit.share) / MAX_BP;
            transfers[i] = IFeeSplits.SplitTransfer({ recipient: feeSplit.recipient, shares: amount });
        }
    }

    function _check(IFeeSplits.FeeSplit[] calldata feeSplits, address stETH) internal pure returns (uint256 len) {
        len = feeSplits.length;
        if (len > MAX_FEE_SPLITS) revert IFeeSplits.TooManySplits();

        uint256 totalShare;
        for (uint256 i; i < len; ++i) {
            IFeeSplits.FeeSplit calldata feeSplit = feeSplits[i];
            if (feeSplit.recipient == address(0)) revert IFeeSplits.ZeroSplitRecipient();
            if (feeSplit.recipient == stETH) revert IFeeSplits.InvalidSplitRecipient();
            if (feeSplit.share == 0) revert IFeeSplits.ZeroSplitShare();
            totalShare += feeSplit.share;
        }

        // totalShare might be lower than MAX_BP. The remainder goes to the
        // Node Operator's bond.
        if (totalShare > MAX_BP) revert IFeeSplits.TooManySplitShares();
    }
}
