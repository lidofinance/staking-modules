// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

// TODO: Think about the other constants to be placed here

/// @dev Basis points denominator (100 % = 10 000 bp).
uint256 constant MAX_BP = 10_000;

/// @dev Maximum weight boost increment; with the baseline, this results in a 10x multiplier.
uint256 constant MAX_WEIGHT_BOOST_BP = 90_000;
