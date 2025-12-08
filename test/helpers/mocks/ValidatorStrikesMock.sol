// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

contract ValidatorStrikesMock {
    constructor() {}

    function processOracleReport(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external {
        // do nothing
    }

    function verifyProof(
        uint256 nodeOperatorId,
        bytes calldata pubkey,
        uint256[] calldata strikesData,
        bytes32[] calldata proof
    ) external view {
        // do nothing
    }
}
