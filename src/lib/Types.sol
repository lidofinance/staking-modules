// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

// As defined in phase0/beacon-chain.md:159
type Slot is uint64;

function unwrap(Slot slot) pure returns (uint64) {
    return Slot.unwrap(slot);
}

function gt(Slot lhs, Slot rhs) pure returns (bool) {
    return lhs.unwrap() > rhs.unwrap();
}

function lt(Slot lhs, Slot rhs) pure returns (bool) {
    return lhs.unwrap() < rhs.unwrap();
}

function gte(Slot lhs, Slot rhs) pure returns (bool) {
    return lhs.unwrap() >= rhs.unwrap();
}

using { unwrap, lt as <, gt as >, gte as >= } for Slot global;

/// @notice Convert gwei to wei
/// @param amount Amount in gwei
function gweiToWei(uint64 amount) pure returns (uint256) {
    return uint256(amount) * 1 gwei;
}

// As defined in capella/beacon-chain.md:99
struct Withdrawal {
    uint64 index;
    uint64 validatorIndex;
    address withdrawalAddress;
    uint64 amount;
}

/// @notice Convert withdrawal amount to wei
/// @param withdrawal Withdrawal struct
function amountWei(Withdrawal memory withdrawal) pure returns (uint256) {
    return gweiToWei(withdrawal.amount);
}

using { amountWei } for Withdrawal global;

// As defined in phase0/beacon-chain.md:356
struct Validator {
    bytes pubkey;
    bytes32 withdrawalCredentials;
    uint64 effectiveBalance;
    bool slashed;
    uint64 activationEligibilityEpoch;
    uint64 activationEpoch;
    uint64 exitEpoch;
    uint64 withdrawableEpoch;
}

// As defined in phase0/beacon-chain.md:436
struct BeaconBlockHeader {
    Slot slot;
    uint64 proposerIndex;
    bytes32 parentRoot;
    bytes32 stateRoot;
    bytes32 bodyRoot;
}
