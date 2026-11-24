// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IResealManager {
    function EMERGENCY_PROTECTED_TIMELOCK() external view returns (address);
}
