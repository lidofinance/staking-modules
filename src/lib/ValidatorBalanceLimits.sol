// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

library ValidatorBalanceLimits {
    uint256 internal constant MIN_ACTIVATION_BALANCE = 32 ether;
    uint256 internal constant MAX_EFFECTIVE_BALANCE = 2048 ether;
    uint256 internal constant MAX_EXTRA_BALANCE = MAX_EFFECTIVE_BALANCE - MIN_ACTIVATION_BALANCE;

    function normalizeExtraBalance(uint256 balanceWei) internal pure returns (uint256) {
        if (balanceWei <= MIN_ACTIVATION_BALANCE) return 0;

        uint256 extraBalance = balanceWei - MIN_ACTIVATION_BALANCE;
        return extraBalance > MAX_EXTRA_BALANCE ? MAX_EXTRA_BALANCE : extraBalance;
    }
}
