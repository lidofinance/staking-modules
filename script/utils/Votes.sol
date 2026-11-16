// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

struct GloasVerifierSwap {
    address module;
    address circuitBreaker;
    address oldVerifier;
    address newVerifier;
}

/// @dev The pending vote of a chain, `artifacts/<chain>/vote.json`.
///      `SimulateVote.run` simulates it until its Dual Governance proposal is executed.
struct VoteConfig {
    /// @dev Zero until the vote submits its proposal to Dual Governance.
    uint256 dgProposalId;
    address dgTimelock;
    GloasVerifierSwap[] gloasVerifiers;
}
