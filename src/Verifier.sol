// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { PausableWithRoles } from "./abstract/PausableWithRoles.sol";

import { BeaconBlockHeader, Slot, Validator, Withdrawal, PendingConsolidation } from "./lib/Types.sol";
import { WithdrawnValidatorLib } from "./lib/WithdrawnValidatorLib.sol";
import { GIndex } from "./lib/GIndex.sol";
import { SSZ } from "./lib/SSZ.sol";

import { IBaseModule, WithdrawnValidatorInfo } from "./interfaces/IBaseModule.sol";
import { IVerifier } from "./interfaces/IVerifier.sol";

/// @notice Convert withdrawal amount to wei
/// @param withdrawal Withdrawal struct
function amountWei(Withdrawal memory withdrawal) pure returns (uint256) {
    return gweiToWei(withdrawal.amount);
}

/// @notice Convert gwei to wei
/// @param amount Amount in gwei
function gweiToWei(uint64 amount) pure returns (uint256) {
    return uint256(amount) * 1 gwei;
}

contract Verifier is IVerifier, AccessControlEnumerable, PausableWithRoles {
    using { amountWei } for Withdrawal;

    using SSZ for PendingConsolidation;
    using SSZ for BeaconBlockHeader;
    using SSZ for Withdrawal;
    using SSZ for Validator;

    // See `BEACON_ROOTS_ADDRESS` constant in the EIP-4788.
    address public constant BEACON_ROOTS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    uint256 internal constant MAX_BP = 10_000;

    /// @dev Minimum withdrawal amount as a ratio of total ether deposited to the validator,
    ///      expressed in basis points (10 000 = 100%). At ~3% top APY, losing >10% of balance
    ///      requires ~3 years offline — implausible for any legitimately run validator.
    ///      We do not accept slashed validators in normal withdrawal processing, so we do not need to account for slashing penalties here.
    ///      In case of unexpected network conditions, the DAO can always replace the verifier contract with one having a different threshold.
    uint256 internal constant MIN_WITHDRAWAL_RATIO = 9000;

    uint64 public immutable SLOTS_PER_EPOCH;

    /// @dev Count of historical roots per accumulator.
    /// @dev See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
    uint64 public immutable SLOTS_PER_HISTORICAL_ROOT;

    /// @dev This index is relative to a state like: `BeaconState.latest_execution_payload_header.withdrawals[0]`.
    GIndex public immutable GI_FIRST_WITHDRAWAL_PREV;

    /// @dev This index is relative to a state like: `BeaconState.latest_execution_payload_header.withdrawals[0]`.
    GIndex public immutable GI_FIRST_WITHDRAWAL_CURR;

    /// @dev This index is relative to a state like: `BeaconState.validators[0]`.
    GIndex public immutable GI_FIRST_VALIDATOR_PREV;

    /// @dev This index is relative to a state like: `BeaconState.validators[0]`.
    GIndex public immutable GI_FIRST_VALIDATOR_CURR;

    /// @dev This index is relative to a state like: `BeaconState.historical_summaries[0]`.
    GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_PREV;

    /// @dev This index is relative to a state like: `BeaconState.historical_summaries[0]`.
    GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_CURR;

    /// @dev This index is relative to HistoricalSummary like: HistoricalSummary.blockRoots[0].
    GIndex public immutable GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV;

    /// @dev This index is relative to HistoricalSummary like: HistoricalSummary.blockRoots[0].
    GIndex public immutable GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR;

    /// @dev This index is relative to a state like: `BeaconState.balances[0]`.
    GIndex public immutable GI_FIRST_BALANCE_NODE_PREV;

    /// @dev This index is relative to a state like: `BeaconState.balances[0]`.
    GIndex public immutable GI_FIRST_BALANCE_NODE_CURR;

    /// @dev This index is relative to a state like: `BeaconState.pending_consolidations[0]`.
    GIndex public immutable GI_FIRST_PENDING_CONSOLIDATION_PREV;

    /// @dev This index is relative to a state like: `BeaconState.pending_consolidations[0]`.
    GIndex public immutable GI_FIRST_PENDING_CONSOLIDATION_CURR;

    /// @dev The very first slot the verifier is supposed to accept proofs for.
    Slot public immutable FIRST_SUPPORTED_SLOT;

    /// @dev The first slot of the currently compatible fork.
    Slot public immutable PIVOT_SLOT;

    /// @dev Historical summaries started accumulating from the slot of Capella fork.
    Slot public immutable CAPELLA_SLOT;

    /// @dev An address withdrawals are supposed to happen to (Lido withdrawal credentials).
    address public immutable WITHDRAWAL_ADDRESS;

    /// @dev Staking module contract.
    IBaseModule public immutable MODULE;

    /// @dev The previous and current forks can be essentially the same.
    constructor(
        address withdrawalAddress,
        address module,
        uint64 slotsPerEpoch,
        uint64 slotsPerHistoricalRoot,
        GIndices memory gindices,
        Slot firstSupportedSlot,
        Slot pivotSlot,
        Slot capellaSlot,
        address admin
    ) {
        if (withdrawalAddress == address(0)) revert ZeroWithdrawalAddress();
        if (module == address(0)) revert ZeroModuleAddress();
        if (admin == address(0)) revert ZeroAdminAddress();
        if (slotsPerEpoch == 0) revert InvalidChainConfig();
        if (slotsPerHistoricalRoot == 0) revert InvalidChainConfig();
        if (firstSupportedSlot > pivotSlot) revert InvalidPivotSlot();
        if (capellaSlot > firstSupportedSlot) revert InvalidCapellaSlot();

        WITHDRAWAL_ADDRESS = withdrawalAddress;
        MODULE = IBaseModule(module);

        SLOTS_PER_EPOCH = slotsPerEpoch;
        SLOTS_PER_HISTORICAL_ROOT = slotsPerHistoricalRoot;

        GI_FIRST_WITHDRAWAL_PREV = gindices.gIFirstWithdrawalPrev;
        GI_FIRST_WITHDRAWAL_CURR = gindices.gIFirstWithdrawalCurr;

        GI_FIRST_VALIDATOR_PREV = gindices.gIFirstValidatorPrev;
        GI_FIRST_VALIDATOR_CURR = gindices.gIFirstValidatorCurr;

        GI_FIRST_HISTORICAL_SUMMARY_PREV = gindices.gIFirstHistoricalSummaryPrev;
        GI_FIRST_HISTORICAL_SUMMARY_CURR = gindices.gIFirstHistoricalSummaryCurr;

        GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV = gindices.gIFirstBlockRootInSummaryPrev;
        GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR = gindices.gIFirstBlockRootInSummaryCurr;

        GI_FIRST_BALANCE_NODE_PREV = gindices.gIFirstBalanceNodePrev;
        GI_FIRST_BALANCE_NODE_CURR = gindices.gIFirstBalanceNodeCurr;

        GI_FIRST_PENDING_CONSOLIDATION_PREV = gindices.gIFirstPendingConsolidationPrev;
        GI_FIRST_PENDING_CONSOLIDATION_CURR = gindices.gIFirstPendingConsolidationCurr;

        FIRST_SUPPORTED_SLOT = firstSupportedSlot;
        PIVOT_SLOT = pivotSlot;
        CAPELLA_SLOT = capellaSlot;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IVerifier
    function processSlashedProof(ProcessSlashedInput calldata data) external whenResumed {
        // TODO: RecentHeaderWitness memory recentBlock = data.recentBlock;
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) revert UnsupportedSlot(data.recentBlock.header.slot);

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        if (!data.validator.object.slashed) revert ValidatorIsNotSlashed();

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex, 1);
            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) revert InvalidPublicKey();
        }

        SSZ.verifyProof({
            proof: data.validator.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.validator.object.hashTreeRoot(),
            gI: _getValidatorGI(data.validator.index, data.recentBlock.header.slot)
        });

        MODULE.onValidatorSlashed(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex);
    }

    /// @inheritdoc IVerifier
    function processWithdrawalProof(ProcessWithdrawalInput calldata data) external whenResumed {
        if (data.withdrawalBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.withdrawalBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.withdrawalBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.withdrawalBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex, 1);
            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) revert InvalidPublicKey();
        }

        uint256 withdrawalAmount = _processWithdrawalProof({
            withdrawal: data.withdrawal,
            validator: data.validator,
            header: data.withdrawalBlock.header,
            // TODO: data.moduleKeyId
            nodeOperatorId: data.moduleKeyId.nodeOperatorId,
            keyIndex: data.moduleKeyId.keyIndex
        });

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                // TODO: data.moduleKeyId
                nodeOperatorId: data.moduleKeyId.nodeOperatorId,
                keyIndex: data.moduleKeyId.keyIndex,
                exitBalance: withdrawalAmount,
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    /// @inheritdoc IVerifier
    function processHistoricalWithdrawalProof(ProcessHistoricalWithdrawalInput calldata data) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) revert UnsupportedSlot(data.recentBlock.header.slot);
        if (data.withdrawalBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.withdrawalBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex, 1);
            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) revert InvalidPublicKey();
        }

        SSZ.verifyProof({
            proof: data.withdrawalBlock.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.withdrawalBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(data.recentBlock.header.slot, data.withdrawalBlock.header.slot)
        });

        uint256 withdrawalAmount = _processWithdrawalProof({
            withdrawal: data.withdrawal,
            validator: data.validator,
            header: data.withdrawalBlock.header,
            nodeOperatorId: data.moduleKeyId.nodeOperatorId,
            keyIndex: data.moduleKeyId.keyIndex
        });

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                nodeOperatorId: data.moduleKeyId.nodeOperatorId,
                keyIndex: data.moduleKeyId.keyIndex,
                exitBalance: withdrawalAmount,
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    // TODO: make historical version + check parent_root
    /// @inheritdoc IVerifier
    function processModuleSourceConsolidation(
        ProcessModuleSourceConsolidationInput calldata data
    ) external whenResumed {
        if (data.consolidationPendingBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.consolidationPendingBlock.header.slot);
        }
        if (data.consolidationAppliedBlock.header.slot <= data.consolidationPendingBlock.header.slot) {
            revert ConsolidationBlockOrderMismatch();
        }

        // Consolidation couldn't have been applied in both of these cases.
        if (data.sourceAtAppliedBlock.object.slashed) revert ValidatorIsSlashed();
        if (
            data.sourceAtAppliedBlock.object.withdrawableEpoch >
            _computeEpochAtSlot(data.consolidationAppliedBlock.header.slot)
        ) {
            revert ValidatorIsNotWithdrawable();
        }

        uint256 sourceIndex = data.consolidation.object.sourceIndex;

        if (data.sourceAtPendingBlock.index != sourceIndex) revert ConsolidationSourceMismatch();
        if (data.sourceAtAppliedBlock.index != sourceIndex) revert ConsolidationSourceMismatch();

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex, 1);
            if (keccak256(pubkey) != keccak256(data.sourceAtAppliedBlock.object.pubkey)) revert InvalidPublicKey();
        }

        // Verify consolidation-applied block's header.
        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.consolidationAppliedBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.consolidationAppliedBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        // Verify consolidation-pending block header.
        SSZ.verifyProof({
            proof: data.consolidationPendingBlock.proof,
            root: data.consolidationAppliedBlock.header.stateRoot,
            leaf: data.consolidationPendingBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(
                data.consolidationAppliedBlock.header.slot,
                data.consolidationPendingBlock.header.slot
            )
        });

        // Verify PendingConsolidation object against the consolidation-pending block.
        SSZ.verifyProof({
            proof: data.consolidation.proof,
            root: data.consolidationPendingBlock.header.stateRoot,
            leaf: data.consolidation.object.hashTreeRoot(),
            gI: _getPendingConsolidationGI(data.consolidation.offset, data.consolidationPendingBlock.header.slot)
        });

        // Verify source at the consolidation-pending block.
        SSZ.verifyProof({
            proof: data.sourceAtPendingBlock.proof,
            root: data.consolidationPendingBlock.header.stateRoot,
            leaf: data.sourceAtPendingBlock.object.hashTreeRoot(),
            gI: _getValidatorGI(sourceIndex, data.consolidationPendingBlock.header.slot)
        });

        // Verify source at the consolidation-applied block.
        SSZ.verifyProof({
            proof: data.sourceAtAppliedBlock.proof,
            root: data.consolidationAppliedBlock.header.stateRoot,
            leaf: data.sourceAtAppliedBlock.object.hashTreeRoot(),
            gI: _getValidatorGI(sourceIndex, data.consolidationAppliedBlock.header.slot)
        });

        // Verify source balance against the consolidation-pending block.
        uint64 pendingBalanceGwei = _verifyValidatorBalance({
            validatorIndex: sourceIndex,
            balanceNode: data.balance.node,
            stateRoot: data.consolidationPendingBlock.header.stateRoot,
            stateSlot: data.consolidationPendingBlock.header.slot,
            proof: data.balance.proof
        });

        uint64 effectiveBalanceGwei = data.sourceAtPendingBlock.object.effectiveBalance;
        uint64 consolidatedBalanceGwei = pendingBalanceGwei < effectiveBalanceGwei
            ? pendingBalanceGwei
            : effectiveBalanceGwei;

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                nodeOperatorId: data.moduleKeyId.nodeOperatorId,
                keyIndex: data.moduleKeyId.keyIndex,
                exitBalance: gweiToWei(consolidatedBalanceGwei),
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    // Continue the next review from here

    /// @inheritdoc IVerifier
    function processModuleTargetConsolidation(
        ProcessModuleTargetConsolidationInput calldata data
    ) external whenResumed {
        if (data.consolidationPendingBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.consolidationPendingBlock.header.slot);
        }
        if (data.consolidationAppliedBlock.header.slot <= data.consolidationPendingBlock.header.slot) {
            revert ConsolidationBlockOrderMismatch();
        }

        // Consolidation couldn't have been applied in both of these cases.
        if (data.sourceAtAppliedBlock.object.slashed) revert ValidatorIsSlashed();
        if (
            _computeEpochAtSlot(data.consolidationAppliedBlock.header.slot) <
            data.sourceAtAppliedBlock.object.withdrawableEpoch
        ) {
            revert ValidatorIsNotWithdrawable();
        }

        uint256 sourceIndex = data.consolidation.object.sourceIndex;

        if (data.sourceAtPendingBlock.index != sourceIndex) {
            revert ConsolidationSourceMismatch();
        }
        if (data.sourceAtAppliedBlock.index != sourceIndex) {
            revert ConsolidationSourceMismatch();
        }
        if (data.targetAtAppliedBlock.index != data.consolidation.object.targetIndex) {
            revert ConsolidationTargetMismatch();
        }

        // Verify the target's pubkey matches the module's key.
        {
            bytes memory pubkey = MODULE.getSigningKeys(data.moduleKeyId.nodeOperatorId, data.moduleKeyId.keyIndex, 1);

            if (keccak256(pubkey) != keccak256(data.targetAtAppliedBlock.object.pubkey)) {
                revert InvalidPublicKey();
            }
        }

        // NOTE: 0x02 withdrawal credential check on the target is not enforced on-chain — enforced by the CL.
        // NOTE: source != target is not enforced on-chain — enforced by the CL.
        // See process_consolidation_request in the beacon spec.

        // Verify consolidation-applied block's header.
        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.consolidationAppliedBlock.rootsTimestamp);
            bytes32 headerRoot = data.consolidationAppliedBlock.header.hashTreeRoot();
            if (trustedHeaderRoot != headerRoot) revert InvalidBlockHeader();
        }

        // Verify consolidation-pending block header.
        SSZ.verifyProof({
            proof: data.consolidationPendingBlock.proof,
            root: data.consolidationAppliedBlock.header.stateRoot,
            leaf: data.consolidationPendingBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(
                data.consolidationAppliedBlock.header.slot,
                data.consolidationPendingBlock.header.slot
            )
        });

        // Verify PendingConsolidation object against the consolidation-pending block.
        SSZ.verifyProof({
            proof: data.consolidation.proof,
            root: data.consolidationPendingBlock.header.stateRoot,
            leaf: data.consolidation.object.hashTreeRoot(),
            gI: _getPendingConsolidationGI(data.consolidation.offset, data.consolidationPendingBlock.header.slot)
        });

        // Verify source at the consolidation-pending block.
        SSZ.verifyProof({
            proof: data.sourceAtPendingBlock.proof,
            root: data.consolidationPendingBlock.header.stateRoot,
            leaf: data.sourceAtPendingBlock.object.hashTreeRoot(),
            gI: _getValidatorGI(sourceIndex, data.consolidationPendingBlock.header.slot)
        });

        // Verify source at the consolidation-applied block.
        SSZ.verifyProof({
            proof: data.sourceAtAppliedBlock.proof,
            root: data.consolidationAppliedBlock.header.stateRoot,
            leaf: data.sourceAtAppliedBlock.object.hashTreeRoot(),
            gI: _getValidatorGI(sourceIndex, data.consolidationAppliedBlock.header.slot)
        });

        // Verify target at the consolidation-applied block.
        SSZ.verifyProof({
            proof: data.targetAtAppliedBlock.proof,
            root: data.consolidationAppliedBlock.header.stateRoot,
            leaf: data.targetAtAppliedBlock.object.hashTreeRoot(),
            gI: _getValidatorGI(data.targetAtAppliedBlock.index, data.consolidationAppliedBlock.header.slot)
        });

        // Verify source balance against the consolidation-pending block.
        uint64 pendingBalanceGwei = _verifyValidatorBalance({
            validatorIndex: sourceIndex,
            balanceNode: data.balance.node,
            stateRoot: data.consolidationPendingBlock.header.stateRoot,
            stateSlot: data.consolidationPendingBlock.header.slot,
            proof: data.balance.proof
        });

        uint64 effectiveBalanceGwei = data.sourceAtPendingBlock.object.effectiveBalance;
        uint64 consolidatedBalanceGwei = pendingBalanceGwei < effectiveBalanceGwei
            ? pendingBalanceGwei
            : effectiveBalanceGwei;

        MODULE.reportIncomingConsolidation({
            nodeOperatorId: data.moduleKeyId.nodeOperatorId,
            keyIndex: data.moduleKeyId.keyIndex,
            sourceValidatorIndex: sourceIndex,
            amount: gweiToWei(consolidatedBalanceGwei)
        });
    }

    function _reportSingleValidator(WithdrawnValidatorInfo memory info) internal {
        WithdrawnValidatorInfo[] memory validatorExits = new WithdrawnValidatorInfo[](1);
        validatorExits[0] = info;
        MODULE.reportRegularWithdrawnValidators(validatorExits);
    }

    function _getParentBlockRoot(uint64 blockTimestamp) internal view returns (bytes32) {
        (bool success, bytes memory data) = BEACON_ROOTS.staticcall(abi.encode(blockTimestamp));

        if (!success || data.length == 0) revert RootNotFound();

        return abi.decode(data, (bytes32));
    }

    /// @dev `header` MUST be trusted at this point.
    function _processWithdrawalProof(
        WithdrawalWitness calldata withdrawal,
        ValidatorWitness calldata validator,
        BeaconBlockHeader calldata header,
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) internal view returns (uint256 withdrawalAmount) {
        if (address(uint160(uint256(validator.object.withdrawalCredentials))) != WITHDRAWAL_ADDRESS) {
            revert InvalidWithdrawalAddress();
        }
        if (withdrawal.object.withdrawalAddress != WITHDRAWAL_ADDRESS) revert InvalidWithdrawalAddress();

        if (validator.object.slashed) revert ValidatorIsSlashed();
        if (validator.object.withdrawableEpoch > _computeEpochAtSlot(header.slot)) revert ValidatorIsNotWithdrawable();
        if (withdrawal.object.validatorIndex != validator.index) revert InvalidValidatorIndex();

        // The full withdrawal threshold is derived from the total ether deposited to the validator (activation balance
        // + tracked top-ups/consolidations). The ratio (MIN_WITHDRAWAL_RATIO / MAX_BP) accounts for possible CL losses
        // such as inactivity penalties.
        uint256 totalDepositedEther = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE +
            MODULE.getKeyAddedBalance(nodeOperatorId, keyIndex);
        withdrawalAmount = withdrawal.object.amountWei();
        if (withdrawalAmount < (totalDepositedEther * MIN_WITHDRAWAL_RATIO) / MAX_BP) revert PartialWithdrawal();

        SSZ.verifyProof({
            proof: validator.proof,
            root: header.stateRoot,
            leaf: validator.object.hashTreeRoot(),
            gI: _getValidatorGI(validator.index, header.slot)
        });

        SSZ.verifyProof({
            proof: withdrawal.proof,
            root: header.stateRoot,
            leaf: withdrawal.object.hashTreeRoot(),
            gI: _getWithdrawalGI(withdrawal.offset, header.slot)
        });
    }

    /// @return balanceGwei Validator's balance in gwei.
    function _verifyValidatorBalance(
        uint256 validatorIndex,
        bytes32 balanceNode,
        bytes32 stateRoot,
        Slot stateSlot,
        bytes32[] calldata proof
    ) internal view returns (uint64 balanceGwei) {
        GIndex gI;

        (gI, balanceGwei) = _getValidatorBalanceNodeInfo(balanceNode, validatorIndex, stateSlot);

        SSZ.verifyProof({ proof: proof, root: stateRoot, leaf: balanceNode, gI: gI });
    }

    /// @return gI Generalized index of the node for the `validatorIndex` and `stateSlot`.
    /// @return balanceGwei Balance in gwei extracted from the `balanceNode`.
    function _getValidatorBalanceNodeInfo(
        bytes32 balanceNode,
        uint256 validatorIndex,
        Slot stateSlot
    ) internal view returns (GIndex gI, uint64 balanceGwei) {
        // `BeaconState.balances` is a list of uint64 values. SSZ packs 4 individual values into a single 32-byte node.
        // Hence, balances[0-3] share the same generalized index.
        gI = _getValidatorBalanceGI(validatorIndex / 4, stateSlot);

        // prettier-ignore
        assembly ("memory-safe") {
            let valueLeftMostBit := mul(64, mod(validatorIndex, 4))
            balanceNode := shl(valueLeftMostBit, balanceNode) // Shift the value to the left side.
            balanceNode := and(balanceNode, 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000)
        }
        // The values are encoded in little-endian order, so we need to convert them to big-endian byte order first.
        balanceNode = SSZ.endianReverse(balanceNode);
        balanceGwei = uint64(uint256(balanceNode));
    }

    function _getValidatorGI(uint256 offset, Slot stateSlot) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT ? GI_FIRST_VALIDATOR_PREV : GI_FIRST_VALIDATOR_CURR;
        return gI.shr(offset);
    }

    function _getWithdrawalGI(uint256 offset, Slot stateSlot) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT ? GI_FIRST_WITHDRAWAL_PREV : GI_FIRST_WITHDRAWAL_CURR;
        return gI.shr(offset);
    }

    function _getValidatorBalanceGI(uint256 offset, Slot stateSlot) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT ? GI_FIRST_BALANCE_NODE_PREV : GI_FIRST_BALANCE_NODE_CURR;
        return gI.shr(offset);
    }

    function _getPendingConsolidationGI(uint256 offset, Slot stateSlot) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT ? GI_FIRST_PENDING_CONSOLIDATION_PREV : GI_FIRST_PENDING_CONSOLIDATION_CURR;
        return gI.shr(offset);
    }

    function _getHistoricalBlockRootGI(Slot recentSlot, Slot targetSlot) internal view returns (GIndex gI) {
        uint64 targetSlotShifted = targetSlot.unwrap() - CAPELLA_SLOT.unwrap();
        uint64 summaryIndex = targetSlotShifted / SLOTS_PER_HISTORICAL_ROOT;
        uint64 rootIndex = targetSlot.unwrap() % SLOTS_PER_HISTORICAL_ROOT;

        Slot summaryCreatedAtSlot = Slot.wrap(targetSlot.unwrap() - rootIndex + SLOTS_PER_HISTORICAL_ROOT);
        if (summaryCreatedAtSlot > recentSlot) revert HistoricalSummaryDoesNotExist();

        gI = recentSlot < PIVOT_SLOT ? GI_FIRST_HISTORICAL_SUMMARY_PREV : GI_FIRST_HISTORICAL_SUMMARY_CURR;

        gI = gI.shr(summaryIndex); // historicalSummaries[summaryIndex]
        gI = gI.concat(
            summaryCreatedAtSlot < PIVOT_SLOT
                ? GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV
                : GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR
        ); // historicalSummaries[summaryIndex].blockRoots[0]
        gI = gI.shr(rootIndex); // historicalSummaries[summaryIndex].blockRoots[rootIndex]
    }

    // From HashConsensus contract.
    function _computeEpochAtSlot(Slot slot) internal view returns (uint256) {
        // See: github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#compute_epoch_at_slot
        return slot.unwrap() / SLOTS_PER_EPOCH;
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
