// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { GIndex } from "./GIndex.sol";

/// @notice Generalized indices of the `BeaconState` fields the `Verifier` builds proofs against.
/// @dev The indices are fork-dependent, and so are the tree shapes they are concatenated with, see
///      `Verifier._getValidatorGI` and the alike. The values can be obtained with `script/gindex.mjs`.
library GIndices {
    /// @dev `BeaconState.latest_execution_payload_header.withdrawals_root`, the withdrawals list root.
    GIndex internal constant WITHDRAWALS_ELECTRA = GIndex.wrap(0xb0e);
    /// @dev `BeaconState.validators`.
    GIndex internal constant VALIDATORS_ELECTRA = GIndex.wrap(0x4b);
    /// @dev `BeaconState.balances`.
    GIndex internal constant BALANCES_ELECTRA = GIndex.wrap(0x4c);
    /// @dev `BeaconState.block_roots`.
    GIndex internal constant BLOCK_ROOTS_ELECTRA = GIndex.wrap(0x45);
    /// @dev `BeaconState.historical_summaries`.
    GIndex internal constant HISTORICAL_SUMMARIES_ELECTRA = GIndex.wrap(0x5b);

    /// @dev `BeaconState.payload_expected_withdrawals`, the withdrawals list itself.
    GIndex internal constant WITHDRAWALS_GLOAS = GIndex.wrap(0xb97);
    /// @dev `BeaconState.validators`.
    GIndex internal constant VALIDATORS_GLOAS = GIndex.wrap(0x166);
    /// @dev `BeaconState.balances`.
    GIndex internal constant BALANCES_GLOAS = GIndex.wrap(0x167);
    /// @dev `BeaconState.block_roots`.
    GIndex internal constant BLOCK_ROOTS_GLOAS = GIndex.wrap(0x160);
    /// @dev `BeaconState.historical_summaries`.
    GIndex internal constant HISTORICAL_SUMMARIES_GLOAS = GIndex.wrap(0xb86);

    /// @dev `HistoricalSummary.block_summary_root`, the block roots vector root. Considered constant
    ///      across forks.
    GIndex internal constant BLOCK_ROOT_IN_SUMMARY = GIndex.wrap(2);
}
