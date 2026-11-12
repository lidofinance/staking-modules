// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { WithdrawalIntent } from "../../../src/interfaces/ITriggerableWithdrawalsGateway.sol";

contract TWGMock {
    uint256 public constant MOCK_REFUND_PERCENTAGE_BP = 1000;

    event Refund(address indexed to, uint256 amount);

    error TransferFailed();

    receive() external payable {}

    function triggerWithdrawals(WithdrawalIntent[] calldata /* intents */, address refundRecipient) external payable {
        uint256 refund = (msg.value * MOCK_REFUND_PERCENTAGE_BP) / 10000;
        if (refund == 0) return;
        (bool success, ) = refundRecipient.call{ value: refund }("");
        if (!success) revert TransferFailed();
    }
}
