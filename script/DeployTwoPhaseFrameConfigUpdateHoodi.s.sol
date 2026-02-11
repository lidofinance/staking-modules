// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployTwoPhaseFrameConfigUpdateBase } from "./DeployTwoPhaseFrameConfigUpdate.s.sol";

contract DeployTwoPhaseFrameConfigUpdateHoodi is DeployTwoPhaseFrameConfigUpdateBase {
    constructor() DeployTwoPhaseFrameConfigUpdateBase("hoodi", 560048) {
        config.reportsToProcessBeforeOffsetPhase = 1;
        config.reportsToProcessBeforeRestorePhase = 1;
        config.offsetPhaseEpochsPerFrame = 2250; // 10 days in epochs (10 * 225)
        config.restorePhaseFastLaneLengthSlots = 64; // ~13 minutes in slots (64 * 12s)
    }
}
