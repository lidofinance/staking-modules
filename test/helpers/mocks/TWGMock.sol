// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { ValidatorData } from "../../../src/interfaces/ITriggerableWithdrawalsGateway.sol";

contract TWGMock {
    uint256 public constant MOCK_REFUND_PERCENTAGE_BP = 1000;

    event Refund(address indexed to, uint256 amount);

    error TransferFailed();

    receive() external payable {}

    function triggerFullWithdrawals(
        ValidatorData[] calldata /* exitData */,
        address refundRecipient,
        uint256 /* exitType */
    ) external payable {
        uint256 refund = (msg.value * MOCK_REFUND_PERCENTAGE_BP) / 10000;
        if (refund == 0) {
            return;
        }
        (bool success, ) = refundRecipient.call{ value: refund }("");
        if (!success) {
            revert TransferFailed();
        }
    }
}
