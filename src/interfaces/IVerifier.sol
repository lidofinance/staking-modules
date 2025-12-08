// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { BeaconBlockHeader, PendingConsolidation, Slot, Validator, Withdrawal } from "../lib/Types.sol";
import { GIndex } from "../lib/GIndex.sol";

import { IBaseModule } from "./IBaseModule.sol";

interface IVerifier {
    struct GIndices {
        GIndex gIFirstWithdrawalPrev;
        GIndex gIFirstWithdrawalCurr;
        GIndex gIFirstValidatorPrev;
        GIndex gIFirstValidatorCurr;
        GIndex gIFirstHistoricalSummaryPrev;
        GIndex gIFirstHistoricalSummaryCurr;
        GIndex gIFirstBlockRootInSummaryPrev;
        GIndex gIFirstBlockRootInSummaryCurr;
        GIndex gIFirstBalanceNodePrev;
        GIndex gIFirstBalanceNodeCurr;
        GIndex gIFirstPendingConsolidationPrev;
        GIndex gIFirstPendingConsolidationCurr;
    }

    struct RecentHeaderWitness {
        BeaconBlockHeader header; // Header of a block which root is a root at rootsTimestamp.
        uint64 rootsTimestamp; // To be passed to the EIP-4788 block roots contract.
    }

    // A witness for a block header which root is accessible via `historical_summaries` field.
    struct HistoricalHeaderWitness {
        BeaconBlockHeader header;
        bytes32[] proof;
    }

    struct WithdrawalWitness {
        uint8 offset; // In the withdrawals list.
        Withdrawal object;
        bytes32[] proof;
    }

    struct ValidatorWitness {
        uint64 index; // Index of a validator in a Beacon state.
        uint32 nodeOperatorId;
        uint32 keyIndex; // Index of the withdrawn key in the Node Operator's keys storage.
        Validator object;
        bytes32[] proof;
    }

    struct BalanceWitness {
        bytes32 node;
        bytes32[] proof;
    }

    struct PendingConsolidationWitness {
        PendingConsolidation object;
        uint64 offset; // in the list of pending consolidations
        bytes32[] proof;
    }

    struct ProcessConsolidationInput {
        PendingConsolidationWitness consolidation;
        ValidatorWitness validator;
        // Represents the validator's balance before the CL processes the pending consolidation. Used as a proxy for the
        // "withdrawal balance" in accounting/penalties, since consolidation is not an EL withdrawal.
        BalanceWitness balance;
        RecentHeaderWitness recentBlock;
        HistoricalHeaderWitness consolidationBlock;
    }

    struct ProcessSlashedInput {
        ValidatorWitness validator;
        RecentHeaderWitness recentBlock;
    }

    struct ProcessWithdrawalInput {
        WithdrawalWitness withdrawal;
        ValidatorWitness validator;
        RecentHeaderWitness withdrawalBlock;
    }

    struct ProcessHistoricalWithdrawalInput {
        WithdrawalWitness withdrawal;
        ValidatorWitness validator;
        RecentHeaderWitness recentBlock;
        HistoricalHeaderWitness withdrawalBlock;
    }

    error RootNotFound();
    error InvalidBlockHeader();
    error InvalidChainConfig();
    error PartialWithdrawal();
    error ValidatorIsSlashed();
    error ValidatorIsNotSlashed();
    error ValidatorIsNotWithdrawable();
    error InvalidWithdrawalAddress();
    error InvalidPublicKey();
    error InvalidConsolidationSource();
    error InvalidValidatorIndex();
    error UnsupportedSlot(Slot slot);
    error ZeroModuleAddress();
    error ZeroWithdrawalAddress();
    error ZeroAdminAddress();
    error InvalidPivotSlot();
    error InvalidCapellaSlot();
    error HistoricalSummaryDoesNotExist();

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function BEACON_ROOTS() external view returns (address);

    function SLOTS_PER_EPOCH() external view returns (uint64);

    function SLOTS_PER_HISTORICAL_ROOT() external view returns (uint64);

    function GI_FIRST_WITHDRAWAL_PREV() external view returns (GIndex);

    function GI_FIRST_WITHDRAWAL_CURR() external view returns (GIndex);

    function GI_FIRST_VALIDATOR_PREV() external view returns (GIndex);

    function GI_FIRST_VALIDATOR_CURR() external view returns (GIndex);

    function GI_FIRST_HISTORICAL_SUMMARY_PREV() external view returns (GIndex);

    function GI_FIRST_HISTORICAL_SUMMARY_CURR() external view returns (GIndex);

    function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV()
        external
        view
        returns (GIndex);

    function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR()
        external
        view
        returns (GIndex);

    function FIRST_SUPPORTED_SLOT() external view returns (Slot);

    function PIVOT_SLOT() external view returns (Slot);

    function CAPELLA_SLOT() external view returns (Slot);

    function WITHDRAWAL_ADDRESS() external view returns (address);

    function MODULE() external view returns (IBaseModule);

    /// @notice Pause write methods calls for `duration` seconds
    /// @param duration Duration of the pause in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Resume write methods calls
    function resume() external;

    /// @notice Verify proof of a slashed validator being withdrawable and report it to the module
    /// @param data @see ProcessSlashedInput
    function processSlashedProof(ProcessSlashedInput calldata data) external;

    /// @notice Verify withdrawal proof and report withdrawal to the module for valid proofs
    /// @notice The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
    /// determining the exact penalty amounts and calling the `IBaseModule.reportWithdrawnValidators` method via an EasyTrack
    /// motion.
    /// @param data @see ProcessWithdrawalInput
    function processWithdrawalProof(
        ProcessWithdrawalInput calldata data
    ) external;

    /// @notice Verify withdrawal proof against historical summaries data and report withdrawal to the module for valid proofs
    /// @notice The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
    /// determining the exact penalty amounts and calling the `IBaseModule.reportWithdrawnValidators` method via an EasyTrack
    /// motion.
    /// @param data @see ProcessHistoricalWithdrawalInput
    function processHistoricalWithdrawalProof(
        ProcessHistoricalWithdrawalInput calldata data
    ) external;

    /// @notice Processes a validator's consolidation from a module's validator. The balance before consolidation is
    /// assumed to be the withdrawal balance.
    /// @dev The caveat is that a pending consolidation is processed later, making it impossible to account for losses
    /// or rewards during the waiting period, as there's no indication of consolidation processing in the state.
    /// @param data @see ProcessConsolidationInput
    function processConsolidation(
        ProcessConsolidationInput calldata data
    ) external;
}
