// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface ICircuitBreaker {
    function registerPauser(address _pausable, address _newPauser) external;

    function pause(address _pausable) external;

    function heartbeat() external;

    function getPauser(address _pausable) external view returns (address);

    function getPausables() external view returns (address[] memory);

    function getPausableCount(address _pauser) external view returns (uint256);

    function isPauserLive(address _pauser) external view returns (bool);

    function pauseDuration() external view returns (uint256);
}
