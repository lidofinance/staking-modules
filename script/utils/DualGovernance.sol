// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IResealManager } from "../interfaces/IResealManager.sol";
import { IEmergencyProtectedTimelock } from "../interfaces/IEmergencyProtectedTimelock.sol";

library DualGovernance {
    function getTimelock(address resealManager) internal view returns (address) {
        return IResealManager(resealManager).EMERGENCY_PROTECTED_TIMELOCK();
    }

    /// @dev A zero `proposalId` stands for a proposal not submitted yet, an unknown one reverts.
    function isProposalExecuted(address timelock, uint256 proposalId) internal view returns (bool) {
        if (proposalId == 0) return false;
        return
            IEmergencyProtectedTimelock(timelock).getProposalDetails(proposalId).status ==
            IEmergencyProtectedTimelock.ProposalStatus.Executed;
    }
}
