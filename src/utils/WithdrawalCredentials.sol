// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

enum WCType {
    BLS,
    Eth1,
    Compounding
}

function toWC(address withdrawalAddress, WCType wcType) pure returns (bytes32) {
    return bytes32(bytes1(uint8(wcType))) | bytes32(uint256(uint160(withdrawalAddress)));
}
