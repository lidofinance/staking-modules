// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

enum WCType {
    Eth1,
    Compounding
}

function toWC(address withdrawalAddress, WCType wcType) pure returns (bytes32) {
    bytes1 prefix = wcType == WCType.Eth1 ? bytes1(0x01) : bytes1(0x02);
    return bytes32(prefix) | bytes32(uint256(uint160(withdrawalAddress)));
}
