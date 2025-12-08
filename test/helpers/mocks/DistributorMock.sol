// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IStETH } from "../../../src/interfaces/IStETH.sol";

contract DistributorMock {
    uint256 internal mockShares;
    IStETH public immutable STETH;
    address public accounting;

    constructor(address stETH) {
        STETH = IStETH(stETH);
    }

    function processOracleReport(
        bytes32 /* treeRoot */,
        string calldata /* treeCid */,
        string calldata /* logCid */,
        uint256 /* distributedShares */,
        uint256 /* rebateShares */,
        uint256 /* refSlot */
    ) external {
        // do nothing
    }

    function getFeesToDistribute(
        uint256 /* nodeOperatorId */,
        uint256 /* shares */,
        bytes32[] calldata /* proof */
    ) public view returns (uint256 sharesToDistribute) {
        return STETH.sharesOf(address(this));
    }

    function setAccounting(address _accounting) external {
        accounting = _accounting;
    }

    function distributeFees(
        uint256 /* nodeOperatorId */,
        uint256 shares,
        bytes32[] calldata /* proof */
    ) external returns (uint256) {
        STETH.transferShares(accounting, shares);
        return shares;
    }
}
