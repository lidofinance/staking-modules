// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ICSAccounting } from "../interfaces/ICSAccounting.sol";
import { ILido } from "../interfaces/ILido.sol";
import { ICSFeeDistributor } from "../interfaces/ICSFeeDistributor.sol";

/// Library for managing FeeSplits
/// @dev the only use of this to be a library is to save CSAccounting contract size via delegatecalls
interface IFeeSplits {
    event FeeSplitsSet(
        uint256 indexed nodeOperatorId,
        ICSAccounting.FeeSplit[] feeSplits
    );

    error PendingOrUndistributedSharesExist();
    error TooManySplits();
    error TooManySplitShares();
    error ZeroSplitRecipient();
    error ZeroSplitShare();
}

library FeeSplits {
    uint256 internal constant MAX_BP = 10_000;
    uint256 public constant MAX_FEE_SPLITS = 5;

    function hasSplits(
        mapping(uint256 => ICSAccounting.FeeSplit[]) storage feeSplitsStorage,
        uint256 nodeOperatorId
    ) external view returns (bool) {
        return feeSplitsStorage[nodeOperatorId].length != 0;
    }

    function setFeeSplits(
        mapping(uint256 => ICSAccounting.FeeSplit[]) storage feeSplitsStorage,
        mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
        ICSFeeDistributor feeDistributor,
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof,
        ICSAccounting.FeeSplit[] calldata feeSplits
    ) external {
        uint256 len = feeSplits.length;
        if (len > MAX_FEE_SPLITS) {
            revert IFeeSplits.TooManySplits();
        }

        if (pendingSharesToSplitStorage[nodeOperatorId] > 0) {
            revert IFeeSplits.PendingOrUndistributedSharesExist();
        }

        if (
            feeDistributor.getFeesToDistribute(
                nodeOperatorId,
                cumulativeFeeShares,
                rewardsProof
            ) != 0
        ) {
            revert IFeeSplits.PendingOrUndistributedSharesExist();
        }

        uint256 totalShare = 0;
        for (uint256 i = 0; i < len; ++i) {
            ICSAccounting.FeeSplit calldata fs = feeSplits[i];
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

        ICSAccounting.FeeSplit[] storage dst = feeSplitsStorage[nodeOperatorId];
        delete feeSplitsStorage[nodeOperatorId];
        for (uint256 i = 0; i < len; i++) {
            dst.push(feeSplits[i]);
        }

        emit IFeeSplits.FeeSplitsSet(nodeOperatorId, feeSplits);
    }

    function splitAndTransferFees(
        mapping(uint256 => ICSAccounting.FeeSplit[]) storage feeSplitsStorage,
        mapping(uint256 => uint256) storage pendingSharesToSplitStorage,
        ILido lido,
        uint256 nodeOperatorId,
        uint256 claimableShares
    ) external returns (uint256 transferred) {
        if (claimableShares == 0) {
            return 0;
        }

        uint256 pending = pendingSharesToSplitStorage[nodeOperatorId];
        if (claimableShares > pending) {
            claimableShares = pending;
        }

        ICSAccounting.FeeSplit[] storage splits = feeSplitsStorage[
            nodeOperatorId
        ];
        uint256 len = splits.length;
        for (uint256 i; i < len; ++i) {
            ICSAccounting.FeeSplit storage feeSplit = splits[i];
            uint256 amount = (claimableShares * feeSplit.share) / MAX_BP;
            if (amount != 0) {
                lido.transferShares(feeSplit.recipient, amount);
                transferred += amount;
            }
        }

        uint256 newPending = pending - claimableShares;
        pendingSharesToSplitStorage[nodeOperatorId] = newPending;
    }
}
