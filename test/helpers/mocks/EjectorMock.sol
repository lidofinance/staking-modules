// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ICSAccounting } from "../../../src/interfaces/ICSAccounting.sol";
import { ICSModule } from "../../../src/interfaces/ICSModule.sol";

contract EjectorMock {
    ICSModule public MODULE;
    ICSAccounting public ACCOUNTING;

    constructor(address _module) {
        MODULE = ICSModule(_module);
    }

    function ejectBadPerformer(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        address refundRecipient
    ) external payable {}
}
