// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

struct WithdrawalIntent {
    uint64 amount;
    bytes pubkey;
}

interface ITriggerableWithdrawalsGateway {
    /**
     * @notice Submits withdrawal requests for all `intents` in order.
     *         A partial withdrawal consumes its amount from the caller's PWR limit,
     *         a full withdrawal consumes one unit from the caller's FWR limit.
     * @param intents Withdrawal intents: `amount == 0` is a full withdrawal, `amount > 0` is a partial one (gwei)
     * @param refundRecipient Receiver of the unused fee; `address(0)` refunds to `msg.sender`
     * @dev Reverts if `intents` exceed either remaining limit of the caller (no partial processing).
     */
    function triggerWithdrawals(WithdrawalIntent[] calldata intents, address refundRecipient) external payable;
}
