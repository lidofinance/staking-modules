// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

// TODO: Think about the other constants to be placed here

/// @dev Basis points denominator (100 % = 10 000 bp).
uint256 constant MAX_BP = 10_000;

/// @dev Upper bound for full effective multipliers (10x = 100 000 bp).
uint256 constant MAX_EFFECTIVE_MULTIPLIER_BP = MAX_BP * 10;

/// @dev Snapshot zero ID means all spaces.
bytes32 constant SNAPSHOT_ALL_SPACES = bytes32(0);
