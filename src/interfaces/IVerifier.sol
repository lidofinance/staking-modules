// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

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

    struct ModuleKeyId {
        uint32 nodeOperatorId;
        uint32 keyIndex; // Index of the key in the Node Operator's keys storage.
    }

    struct ValidatorWitness {
        uint64 index; // Index of a validator in a Beacon state.
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

    struct ProcessModuleSourceConsolidationInput {
        PendingConsolidationWitness consolidation;
        // Source validator state before the consolidation is processed by the CL.
        // Proved against the consolidation block.
        ValidatorWitness sourceValidatorBeforeConsolidation;
        // Source validator state after the consolidation is processed by the CL.
        // Proved against the recent block.
        ValidatorWitness sourceValidatorAfterConsolidation;
        ModuleKeyId moduleKeyId;
        // Source validator's balance before the CL processes the pending consolidation. Used as a proxy for the
        // "withdrawal balance" in accounting/penalties, since consolidation is not an EL withdrawal.
        BalanceWitness balance;
        RecentHeaderWitness recentBlock;
        HistoricalHeaderWitness consolidationBlock;
    }

    struct ProcessSlashedInput {
        ValidatorWitness validator;
        ModuleKeyId moduleKeyId;
        RecentHeaderWitness recentBlock;
    }

    struct ProcessWithdrawalInput {
        WithdrawalWitness withdrawal;
        ValidatorWitness validator;
        ModuleKeyId moduleKeyId;
        RecentHeaderWitness withdrawalBlock;
    }

    struct ProcessHistoricalWithdrawalInput {
        WithdrawalWitness withdrawal;
        ValidatorWitness validator;
        ModuleKeyId moduleKeyId;
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
    error SourceValidatorIndexMismatch();
    error InvalidValidatorIndex();
    error UnsupportedSlot(Slot slot);
    error ZeroModuleAddress();
    error ZeroWithdrawalAddress();
    error ZeroAdminAddress();
    error InvalidPivotSlot();
    error InvalidCapellaSlot();
    error HistoricalSummaryDoesNotExist();
    error NotImplemented();

    function BEACON_ROOTS() external view returns (address);

    function SLOTS_PER_EPOCH() external view returns (uint64);

    function SLOTS_PER_HISTORICAL_ROOT() external view returns (uint64);

    function GI_FIRST_WITHDRAWAL_PREV() external view returns (GIndex);

    function GI_FIRST_WITHDRAWAL_CURR() external view returns (GIndex);

    function GI_FIRST_VALIDATOR_PREV() external view returns (GIndex);

    function GI_FIRST_VALIDATOR_CURR() external view returns (GIndex);

    function GI_FIRST_HISTORICAL_SUMMARY_PREV() external view returns (GIndex);

    function GI_FIRST_HISTORICAL_SUMMARY_CURR() external view returns (GIndex);

    function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV() external view returns (GIndex);

    function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR() external view returns (GIndex);

    function FIRST_SUPPORTED_SLOT() external view returns (Slot);

    function PIVOT_SLOT() external view returns (Slot);

    function CAPELLA_SLOT() external view returns (Slot);

    function WITHDRAWAL_ADDRESS() external view returns (address);

    function MODULE() external view returns (IBaseModule);

    /// @notice Verify proof of a slashed validator being withdrawable and report it to the module
    /// @param data @see ProcessSlashedInput
    function processSlashedProof(ProcessSlashedInput calldata data) external;

    /// @notice Verify withdrawal proof and report withdrawal to the module for valid proofs
    /// @notice The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
    /// determining the exact penalty amounts and calling the `IBaseModule.reportSlashedWithdrawnValidators` method via
    /// an EasyTrack motion.
    /// @param data @see ProcessWithdrawalInput
    function processWithdrawalProof(ProcessWithdrawalInput calldata data) external;

    /// @notice Verify withdrawal proof against historical summaries data and report withdrawal to the module for valid proofs
    /// @notice The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
    /// determining the exact penalty amounts and calling the `IBaseModule.reportSlashedWithdrawnValidators` method via
    /// an EasyTrack motion.
    /// @param data @see ProcessHistoricalWithdrawalInput
    function processHistoricalWithdrawalProof(ProcessHistoricalWithdrawalInput calldata data) external;

    /// @notice Processes a validator's consolidation from a module's validator. The source validator's balance and
    /// effective balance before consolidation are used as a proxy for the "withdrawal balance" in accounting/penalties.
    /// @dev The source validator is proved at two points in time: when pending consolidation exists (consolidation
    /// block state) to get balances of the validator at this point, and after consolidation (recent block state) for
    /// validator status checks. The caveat is that a pending consolidation is processed at unknown point in time
    /// between these two points, as there's no indication of consolidation processing in the state. By using the
    /// pre-consolidation balance as a withdrawal one, we do not account for losses or rewards accrued while the
    /// consolidation was in the pending state.
    /// @param data @see ProcessModuleSourceConsolidationInput
    function processModuleSourceConsolidation(ProcessModuleSourceConsolidationInput calldata data) external;

    /// @notice Stub method for incoming consolidation request proofs.
    function processIncomingConsolidation(uint256 nodeOperatorId, uint256 keyIndex, uint256 addedBalanceWei) external;
}
