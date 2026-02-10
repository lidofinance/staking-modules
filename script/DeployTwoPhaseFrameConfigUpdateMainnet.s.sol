// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployTwoPhaseFrameConfigUpdateBase } from "./DeployTwoPhaseFrameConfigUpdate.s.sol";

contract DeployTwoPhaseFrameConfigUpdateMainnet is DeployTwoPhaseFrameConfigUpdateBase {
    constructor() DeployTwoPhaseFrameConfigUpdateBase("mainnet", 1) {
        config.reportsToProcessBeforeOffsetPhase = 2;
        config.reportsToProcessBeforeRestorePhase = 1;
        config.offsetPhaseEpochsPerFrame = 6975; // 31 days in epochs (31 * 225)
        config.restorePhaseFastLaneLengthSlots = 300; // 1 hour in slots (300 * 12s = 3600s)
    }
}
