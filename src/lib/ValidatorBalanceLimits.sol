// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

library ValidatorBalanceLimits {
    uint256 internal constant MIN_ACTIVATION_BALANCE = 32 ether;
    uint256 internal constant MAX_EFFECTIVE_BALANCE = 2048 ether;
}
