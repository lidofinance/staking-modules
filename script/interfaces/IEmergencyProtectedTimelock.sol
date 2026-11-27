// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IEmergencyProtectedTimelock {
    enum ProposalStatus {
        NotExist,
        Submitted,
        Scheduled,
        Executed,
        Cancelled
    }

    struct ProposalDetails {
        uint256 id;
        address executor;
        uint40 submittedAt;
        uint40 scheduledAt;
        ProposalStatus status;
    }

    /// @dev Reverts for a proposal that does not exist.
    function getProposalDetails(uint256 proposalId) external view returns (ProposalDetails memory);
}
