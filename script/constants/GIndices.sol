// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { GIndex } from "../../src/lib/GIndex.sol";
import { IVerifier } from "../../src/interfaces/IVerifier.sol";

library GIndices {
    GIndex public constant WITHDRAWALS_ELECTRA = GIndex.wrap(0xb0e);
    GIndex public constant VALIDATORS_ELECTRA = GIndex.wrap(0x4b);
    GIndex public constant BALANCES_ELECTRA = GIndex.wrap(0x4c);
    GIndex public constant BLOCK_ROOTS_ELECTRA = GIndex.wrap(0x45);
    GIndex public constant HISTORICAL_SUMMARIES_ELECTRA = GIndex.wrap(0x5b);

    GIndex public constant WITHDRAWALS_GLOAS = GIndex.wrap(0xb97);
    GIndex public constant VALIDATORS_GLOAS = GIndex.wrap(0x166);
    GIndex public constant BALANCES_GLOAS = GIndex.wrap(0x167);
    GIndex public constant BLOCK_ROOTS_GLOAS = GIndex.wrap(0x160);
    GIndex public constant HISTORICAL_SUMMARIES_GLOAS = GIndex.wrap(0xb86);

    function electraToGloas() internal pure returns (IVerifier.GIndices memory) {
        return
            IVerifier.GIndices({
                gIWithdrawalsPreGloas: WITHDRAWALS_ELECTRA,
                gIWithdrawals: WITHDRAWALS_GLOAS,
                gIValidatorsPreGloas: VALIDATORS_ELECTRA,
                gIValidators: VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: HISTORICAL_SUMMARIES_ELECTRA,
                gIHistoricalSummaries: HISTORICAL_SUMMARIES_GLOAS,
                gIBalancesPreGloas: BALANCES_ELECTRA,
                gIBalances: BALANCES_GLOAS,
                gIBlockRootsPreGloas: BLOCK_ROOTS_ELECTRA,
                gIBlockRoots: BLOCK_ROOTS_GLOAS
            });
    }
}
