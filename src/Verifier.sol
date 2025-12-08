// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { BeaconBlockHeader, Slot, Validator, Withdrawal, PendingConsolidation } from "./lib/Types.sol";
import { PausableUntil } from "./lib/utils/PausableUntil.sol";
import { GIndex } from "./lib/GIndex.sol";
import { SSZ } from "./lib/SSZ.sol";

import { IVerifier } from "./interfaces/IVerifier.sol";
import { IBaseModule, WithdrawnValidatorInfo } from "./interfaces/IBaseModule.sol";

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

contract Verifier is IVerifier, AccessControlEnumerable, PausableUntil {
    using { amountWei } for Withdrawal;

    using SSZ for PendingConsolidation;
    using SSZ for BeaconBlockHeader;
    using SSZ for Withdrawal;
    using SSZ for Validator;

    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");

    // See `BEACON_ROOTS_ADDRESS` constant in the EIP-4788.
    address public constant BEACON_ROOTS =
        0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

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
    GIndex public immutable GI_FIRST_BALANCES_NODE_PREV;

    /// @dev This index is relative to a state like: `BeaconState.balances[0]`.
    GIndex public immutable GI_FIRST_BALANCES_NODE_CURR;

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
        if (withdrawalAddress == address(0)) {
            revert ZeroWithdrawalAddress();
        }

        if (module == address(0)) {
            revert ZeroModuleAddress();
        }

        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        if (slotsPerEpoch == 0) {
            revert InvalidChainConfig();
        }

        if (slotsPerHistoricalRoot == 0) {
            revert InvalidChainConfig();
        }

        if (firstSupportedSlot > pivotSlot) {
            revert InvalidPivotSlot();
        }

        if (capellaSlot > firstSupportedSlot) {
            revert InvalidCapellaSlot();
        }

        WITHDRAWAL_ADDRESS = withdrawalAddress;
        MODULE = IBaseModule(module);

        SLOTS_PER_EPOCH = slotsPerEpoch;
        SLOTS_PER_HISTORICAL_ROOT = slotsPerHistoricalRoot;

        GI_FIRST_WITHDRAWAL_PREV = gindices.gIFirstWithdrawalPrev;
        GI_FIRST_WITHDRAWAL_CURR = gindices.gIFirstWithdrawalCurr;

        GI_FIRST_VALIDATOR_PREV = gindices.gIFirstValidatorPrev;
        GI_FIRST_VALIDATOR_CURR = gindices.gIFirstValidatorCurr;

        GI_FIRST_HISTORICAL_SUMMARY_PREV = gindices
            .gIFirstHistoricalSummaryPrev;
        GI_FIRST_HISTORICAL_SUMMARY_CURR = gindices
            .gIFirstHistoricalSummaryCurr;

        GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV = gindices
            .gIFirstBlockRootInSummaryPrev;
        GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR = gindices
            .gIFirstBlockRootInSummaryCurr;

        GI_FIRST_BALANCES_NODE_PREV = gindices.gIFirstBalanceNodePrev;
        GI_FIRST_BALANCES_NODE_CURR = gindices.gIFirstBalanceNodeCurr;

        GI_FIRST_PENDING_CONSOLIDATION_PREV = gindices
            .gIFirstPendingConsolidationPrev;
        GI_FIRST_PENDING_CONSOLIDATION_CURR = gindices
            .gIFirstPendingConsolidationCurr;

        FIRST_SUPPORTED_SLOT = firstSupportedSlot;
        PIVOT_SLOT = pivotSlot;
        CAPELLA_SLOT = capellaSlot;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IVerifier
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc IVerifier
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc IVerifier
    function processSlashedProof(
        ProcessSlashedInput calldata data
    ) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.recentBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(
                data.recentBlock.rootsTimestamp
            );
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) {
                revert InvalidBlockHeader();
            }
        }

        if (!data.validator.object.slashed) {
            revert ValidatorIsNotSlashed();
        }

        // TODO: Consider uncommenting or removing the block.
        // if (
        //     _computeEpochAtSlot(data.recentBlock.header.slot) <
        //     data.validator.object.withdrawableEpoch
        // ) {
        //     revert ValidatorIsNotWithdrawable();
        // }

        {
            bytes memory pubkey = MODULE.getSigningKeys(
                data.validator.nodeOperatorId,
                data.validator.keyIndex,
                1
            );

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) {
                revert InvalidPublicKey();
            }
        }

        SSZ.verifyProof({
            proof: data.validator.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.validator.object.hashTreeRoot(),
            gI: _getValidatorGI(
                data.validator.index,
                data.recentBlock.header.slot
            )
        });

        MODULE.onValidatorSlashed(
            data.validator.nodeOperatorId,
            data.validator.keyIndex
        );
    }

    /// @inheritdoc IVerifier
    function processWithdrawalProof(
        ProcessWithdrawalInput calldata data
    ) external whenResumed {
        if (data.withdrawalBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.withdrawalBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(
                data.withdrawalBlock.rootsTimestamp
            );
            if (
                trustedHeaderRoot != data.withdrawalBlock.header.hashTreeRoot()
            ) {
                revert InvalidBlockHeader();
            }
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(
                data.validator.nodeOperatorId,
                data.validator.keyIndex,
                1
            );

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) {
                revert InvalidPublicKey();
            }
        }

        uint256 withdrawalAmount = _processWithdrawalProof(
            data.withdrawal,
            data.validator,
            data.withdrawalBlock.header
        );

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                nodeOperatorId: data.validator.nodeOperatorId,
                keyIndex: data.validator.keyIndex,
                exitBalance: withdrawalAmount,
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    /// @inheritdoc IVerifier
    function processHistoricalWithdrawalProof(
        ProcessHistoricalWithdrawalInput calldata data
    ) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.recentBlock.header.slot);
        }

        if (data.withdrawalBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.withdrawalBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(
                data.recentBlock.rootsTimestamp
            );
            bytes32 headerRoot = data.recentBlock.header.hashTreeRoot();
            if (trustedHeaderRoot != headerRoot) {
                revert InvalidBlockHeader();
            }
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(
                data.validator.nodeOperatorId,
                data.validator.keyIndex,
                1
            );

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) {
                revert InvalidPublicKey();
            }
        }

        SSZ.verifyProof({
            proof: data.withdrawalBlock.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.withdrawalBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(
                data.recentBlock.header.slot,
                data.withdrawalBlock.header.slot
            )
        });

        uint256 withdrawalAmount = _processWithdrawalProof(
            data.withdrawal,
            data.validator,
            data.withdrawalBlock.header
        );

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                nodeOperatorId: data.validator.nodeOperatorId,
                keyIndex: data.validator.keyIndex,
                exitBalance: withdrawalAmount,
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    /// @inheritdoc IVerifier
    function processConsolidation(
        ProcessConsolidationInput calldata data
    ) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.recentBlock.header.slot);
        }

        if (data.consolidationBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.consolidationBlock.header.slot);
        }

        if (data.validator.object.slashed) {
            revert ValidatorIsSlashed();
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(
                data.validator.nodeOperatorId,
                data.validator.keyIndex,
                1
            );

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) {
                revert InvalidPublicKey();
            }
        }

        if (
            _computeEpochAtSlot(data.recentBlock.header.slot) <
            data.validator.object.withdrawableEpoch
        ) {
            revert ValidatorIsNotWithdrawable();
        }

        if (data.consolidation.object.sourceIndex != data.validator.index) {
            revert InvalidConsolidationSource();
        }

        // Verify recent block's header.
        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(
                data.recentBlock.rootsTimestamp
            );
            bytes32 headerRoot = data.recentBlock.header.hashTreeRoot();
            if (trustedHeaderRoot != headerRoot) {
                revert InvalidBlockHeader();
            }
        }

        // Verify consolidation block header.
        SSZ.verifyProof({
            proof: data.consolidationBlock.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.consolidationBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(
                data.recentBlock.header.slot,
                data.consolidationBlock.header.slot
            )
        });

        // Verify PendingConsolidation object against the consolidation block.
        SSZ.verifyProof({
            proof: data.consolidation.proof,
            root: data.consolidationBlock.header.stateRoot,
            leaf: data.consolidation.object.hashTreeRoot(),
            gI: _getPendingConsolidationGI(
                data.consolidation.offset,
                data.consolidationBlock.header.slot
            )
        });

        // Verify Validator object against the recent block.
        SSZ.verifyProof({
            proof: data.validator.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.validator.object.hashTreeRoot(),
            gI: _getValidatorGI(
                data.validator.index,
                data.recentBlock.header.slot
            )
        });

        // Verify validator's balance against the consolidation block.
        uint64 balanceGwei = _verifyValidatorBalance({
            validatorIndex: data.validator.index,
            balanceNode: data.balance.node,
            stateRoot: data.consolidationBlock.header.stateRoot,
            stateSlot: data.consolidationBlock.header.slot,
            proof: data.balance.proof
        });

        _reportSingleValidator(
            WithdrawnValidatorInfo({
                nodeOperatorId: data.validator.nodeOperatorId,
                keyIndex: data.validator.keyIndex,
                exitBalance: gweiToWei(balanceGwei),
                slashingPenalty: 0,
                isSlashed: false
            })
        );
    }

    function _reportSingleValidator(
        WithdrawnValidatorInfo memory info
    ) internal {
        WithdrawnValidatorInfo[]
            memory validatorExits = new WithdrawnValidatorInfo[](1);
        validatorExits[0] = info;
        MODULE.reportWithdrawnValidators(validatorExits);
    }

    function _getParentBlockRoot(
        uint64 blockTimestamp
    ) internal view returns (bytes32) {
        (bool success, bytes memory data) = BEACON_ROOTS.staticcall(
            abi.encode(blockTimestamp)
        );

        if (!success || data.length == 0) {
            revert RootNotFound();
        }

        return abi.decode(data, (bytes32));
    }

    /// @dev `header` MUST be trusted at this point.
    function _processWithdrawalProof(
        WithdrawalWitness calldata withdrawal,
        ValidatorWitness calldata validator,
        BeaconBlockHeader calldata header
    ) internal view returns (uint256 withdrawalAmount) {
        if (
            address(uint160(uint256(validator.object.withdrawalCredentials))) !=
            WITHDRAWAL_ADDRESS
        ) {
            revert InvalidWithdrawalAddress();
        }
        if (withdrawal.object.withdrawalAddress != WITHDRAWAL_ADDRESS) {
            revert InvalidWithdrawalAddress();
        }

        // The methods in this contract do not accept proofs of withdrawals from slashed validators. It is proposed that
        // such withdrawals be processed off-chain and reported directly to the CSModule using EasyTracks.
        if (validator.object.slashed) {
            revert ValidatorIsSlashed();
        }

        if (
            _computeEpochAtSlot(header.slot) <
            validator.object.withdrawableEpoch
        ) {
            revert ValidatorIsNotWithdrawable();
        }

        if (withdrawal.object.validatorIndex != validator.index) {
            revert InvalidValidatorIndex();
        }

        // See https://hackmd.io/1wM8vqeNTjqt4pC3XoCUKQ
        //
        // ISSUE:
        // There is a possible way to bypass this check:
        // - wait for full withdrawal & sweep
        // - be lucky enough that no one provides proof for this withdrawal for at least 1 sweep cycle
        //  (~8 days with the network of 1M active validators)
        // - deposit 15 ETH for non-slashed validator
        // - wait for a sweep of this deposit
        // - provide proof of the last withdrawal
        // As a result, the Node Operator's bond will be penalized for 32 ETH - additional deposit value
        // However, all ETH involved,
        // including 15 ETH deposited by the attacker will remain in the Lido on Ethereum protocol
        // Hence, the only consequence of the attack is an inconsistency in the bond accounting that can be resolved
        // through the bond deposit approved by the corresponding DAO decision
        //
        // Resolution:
        // Given no losses for the protocol,
        // significant cost of attack (15 ETH),
        // and lack of feasible ways to mitigate it in the smart contract's code,
        // it is proposed to acknowledge possibility of the attack
        // and be ready to propose a corresponding vote to the DAO if it will ever happen
        withdrawalAmount = withdrawal.object.amountWei();
        if (withdrawalAmount < 15 ether) {
            revert PartialWithdrawal();
        }

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

        (gI, balanceGwei) = _getValidatorBalanceNodeInfo(
            balanceNode,
            validatorIndex,
            stateSlot
        );

        SSZ.verifyProof({
            proof: proof,
            root: stateRoot,
            leaf: balanceNode,
            gI: gI
        });
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

    function _getValidatorGI(
        uint256 offset,
        Slot stateSlot
    ) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT
            ? GI_FIRST_VALIDATOR_PREV
            : GI_FIRST_VALIDATOR_CURR;
        return gI.shr(offset);
    }

    function _getWithdrawalGI(
        uint256 offset,
        Slot stateSlot
    ) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT
            ? GI_FIRST_WITHDRAWAL_PREV
            : GI_FIRST_WITHDRAWAL_CURR;
        return gI.shr(offset);
    }

    function _getValidatorBalanceGI(
        uint256 offset,
        Slot stateSlot
    ) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT
            ? GI_FIRST_BALANCES_NODE_PREV
            : GI_FIRST_BALANCES_NODE_CURR;
        return gI.shr(offset);
    }

    function _getPendingConsolidationGI(
        uint256 offset,
        Slot stateSlot
    ) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT
            ? GI_FIRST_PENDING_CONSOLIDATION_PREV
            : GI_FIRST_PENDING_CONSOLIDATION_CURR;
        return gI.shr(offset);
    }

    function _getHistoricalBlockRootGI(
        Slot recentSlot,
        Slot targetSlot
    ) internal view returns (GIndex gI) {
        uint64 targetSlotShifted = targetSlot.unwrap() - CAPELLA_SLOT.unwrap();
        uint64 summaryIndex = targetSlotShifted / SLOTS_PER_HISTORICAL_ROOT;
        uint64 rootIndex = targetSlot.unwrap() % SLOTS_PER_HISTORICAL_ROOT;

        Slot summaryCreatedAtSlot = Slot.wrap(
            targetSlot.unwrap() - rootIndex + SLOTS_PER_HISTORICAL_ROOT
        );
        if (summaryCreatedAtSlot > recentSlot) {
            revert HistoricalSummaryDoesNotExist();
        }

        gI = recentSlot < PIVOT_SLOT
            ? GI_FIRST_HISTORICAL_SUMMARY_PREV
            : GI_FIRST_HISTORICAL_SUMMARY_CURR;

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
}
