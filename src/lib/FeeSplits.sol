// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IAccounting } from "../interfaces/IAccounting.sol";
import { ILido } from "../interfaces/ILido.sol";
import { IFeeDistributor } from "../interfaces/IFeeDistributor.sol";

/// Library for managing FeeSplits
/// @dev the only use of this to be a library is to save Accounting contract size via delegatecalls
interface IFeeSplits {
    event FeeSplitsSet(
        uint256 indexed nodeOperatorId,
        IAccounting.FeeSplit[] feeSplits
    );

    error PendingSharesExist();
    error UndistributedSharesExist();
    error TooManySplits();
    error TooManySplitShares();
    error ZeroSplitRecipient();
    error ZeroSplitShare();
}

library FeeSplits {
    uint256 internal constant MAX_BP = 10_000;
    uint256 public constant MAX_FEE_SPLITS = 10;

    function setFeeSplits(
        mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage,
        mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
        IFeeDistributor feeDistributor,
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof,
        IAccounting.FeeSplit[] calldata feeSplits
    ) external {
        uint256 len = feeSplits.length;
        if (len > MAX_FEE_SPLITS) {
            revert IFeeSplits.TooManySplits();
        }

        if (pendingSharesToSplitStorage[nodeOperatorId] > 0) {
            revert IFeeSplits.PendingSharesExist();
        }

        if (
            feeDistributor.getFeesToDistribute(
                nodeOperatorId,
                cumulativeFeeShares,
                rewardsProof
            ) != 0
        ) {
            revert IFeeSplits.UndistributedSharesExist();
        }

        uint256 totalShare = 0;
        for (uint256 i = 0; i < len; ++i) {
            IAccounting.FeeSplit calldata fs = feeSplits[i];
            if (fs.recipient == address(0)) {
                revert IFeeSplits.ZeroSplitRecipient();
            }
            if (fs.share == 0) {
                revert IFeeSplits.ZeroSplitShare();
            }
            totalShare += fs.share;
        }
        // totalShare might be lower than MAX_BP. The remainder goes to the Node Operator's bond
        if (totalShare > MAX_BP) {
            revert IFeeSplits.TooManySplitShares();
        }

        IAccounting.FeeSplit[] storage dst = feeSplitsStorage[nodeOperatorId];
        delete feeSplitsStorage[nodeOperatorId];
        for (uint256 i = 0; i < len; i++) {
            dst.push(feeSplits[i]);
        }

        emit IFeeSplits.FeeSplitsSet(nodeOperatorId, feeSplits);
    }

    function splitAndTransferFees(
        mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage,
        mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
        ILido lido,
        uint256 nodeOperatorId,
        uint256 maxSharesToSplit
    ) external returns (uint256 transferred) {
        if (maxSharesToSplit == 0) {
            return 0;
        }

        // NOTE: `pending` is stETH shares. It contains operator's and splits recipients' parts. May accumulate over time.
        uint256 pending = pendingSharesToSplitStorage[nodeOperatorId];
        if (maxSharesToSplit > pending) {
            maxSharesToSplit = pending;
        }

        IAccounting.FeeSplit[] storage splits = feeSplitsStorage[
            nodeOperatorId
        ];
        uint256 len = splits.length;
        for (uint256 i; i < len; ++i) {
            IAccounting.FeeSplit storage feeSplit = splits[i];
            // NOTE: Due to rounding error, final operator's part might contain some dust.
            //      There is a known issue that the transfer amount may differ slightly depending on when the split was made due to `pending` accumulation.
            uint256 amount = (maxSharesToSplit * feeSplit.share) / MAX_BP;
            if (amount != 0) {
                lido.transferShares(feeSplit.recipient, amount);
                transferred += amount;
            }
        }

        // NOTE: Most of the time `newPending` will be 0 after the split.
        //      It might be non-zero in case of operator's debt due to bond lock or any other reason of bond insufficiency.
        uint256 newPending = pending - maxSharesToSplit;
        pendingSharesToSplitStorage[nodeOperatorId] = newPending;
    }

    function hasSplits(
        mapping(uint256 => IAccounting.FeeSplit[]) storage feeSplitsStorage,
        uint256 nodeOperatorId
    ) external view returns (bool) {
        return feeSplitsStorage[nodeOperatorId].length != 0;
    }
}
