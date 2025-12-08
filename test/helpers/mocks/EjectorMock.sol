// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IAccounting } from "../../../src/interfaces/IAccounting.sol";
import { ICSModule } from "../../../src/interfaces/ICSModule.sol";

contract EjectorMock {
    ICSModule public MODULE;
    IAccounting public ACCOUNTING;

    constructor(address _module) {
        MODULE = ICSModule(_module);
    }

    function ejectBadPerformer(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        address refundRecipient
    ) external payable {}
}
