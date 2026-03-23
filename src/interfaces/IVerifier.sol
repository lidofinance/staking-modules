// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BeaconBlockHeader, Slot, Validator, Withdrawal } from "../lib/Types.sol";
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

    struct ProcessBalanceProofInput {
        RecentHeaderWitness recentBlock;
        ValidatorWitness validator;
        BalanceWitness balance;
    }

    struct ProcessHistoricalBalanceProofInput {
        RecentHeaderWitness recentBlock;
        HistoricalHeaderWitness historicalBlock;
        ValidatorWitness validator;
        BalanceWitness balance;
    }

    error RootNotFound();
    error InvalidBlockHeader();
    error InvalidChainConfig();
    error PartialWithdrawal();
    error ValidatorIsSlashed();
    error ValidatorIsNotSlashed();
    error ValidatorIsNotWithdrawable();
    error ValidatorIsWithdrawable();
    error InvalidWithdrawalAddress();
    error InvalidPublicKey();
    error InvalidValidatorIndex();
    error UnsupportedSlot(Slot slot);
    error ZeroModuleAddress();
    error ZeroWithdrawalAddress();
    error ZeroAdminAddress();
    error InvalidPivotSlot();
    error InvalidCapellaSlot();
    error InvalidMinWithdrawalRatio();
    error HistoricalSummaryDoesNotExist();

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

    function MIN_WITHDRAWAL_RATIO() external view returns (uint256);

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

    /// @notice Verify a validator's balance proof from a recent beacon block and sync the key added balance.
    /// @param data The balance proof input containing recent block header, validator witness, and balance witness.
    function processBalanceProof(ProcessBalanceProofInput calldata data) external;

    /// @notice Verify a validator's balance proof from a historical beacon block and sync the key added balance.
    ///         A historical proof is needed because the validator's balance may have increased at some point in the past
    ///         and later decreased (e.g. due to inactivity leak or penalties). A recent proof alone would miss that peak,
    ///         so a historical proof allows capturing the highest observed balance.
    /// @param data The balance proof input containing recent + historical block headers, validator witness, and balance witness.
    function processHistoricalBalanceProof(ProcessHistoricalBalanceProofInput calldata data) external;
}
