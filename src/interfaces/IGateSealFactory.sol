// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IGateSealFactory {
    event GateSealCreated(address gateSeal);

    function create_gate_seal(
        address sealingCommittee,
        uint256 sealDurationSeconds,
        address[] memory sealables,
        uint256 expiryTimestamp
    ) external;
}
