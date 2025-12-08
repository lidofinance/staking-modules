// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

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

using { unwrap, lt as <, gt as > } for Slot global;

// As defined in capella/beacon-chain.md:99
struct Withdrawal {
    uint64 index;
    uint64 validatorIndex;
    address withdrawalAddress;
    uint64 amount;
}

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

// As defined in electra/beacon-chain.md:251
struct PendingConsolidation {
    uint64 sourceIndex;
    uint64 targetIndex;
}
