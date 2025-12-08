// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

/// @author skhomuti
library ValidatorCountsReport {
    error InvalidReportData();

    function safeCountOperators(
        bytes calldata ids,
        bytes calldata counts
    ) internal pure returns (uint256 len) {
        bool ok;

        assembly ("memory-safe") {
            len := div(ids.length, 8)

            ok := and(
                eq(ids.length, mul(len, 8)),
                eq(counts.length, mul(len, 16))
            )
        }

        if (!ok) {
            revert InvalidReportData();
        }
    }

    function next(
        bytes calldata ids,
        bytes calldata counts,
        uint256 offset
    ) internal pure returns (uint256 nodeOperatorId, uint256 keysCount) {
        // prettier-ignore
        assembly ("memory-safe") {
            nodeOperatorId := shr(192, calldataload(add(ids.offset, mul(offset, 8))))
            keysCount := shr(128, calldataload(add(counts.offset, mul(offset, 16))))
        }
    }
}
