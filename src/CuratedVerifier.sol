// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { BeaconBlockHeader, Slot, Validator } from "./lib/Types.sol";
import { PausableWithRoles } from "./abstract/PausableWithRoles.sol";
import { GIndex } from "./lib/GIndex.sol";
import { SSZ } from "./lib/SSZ.sol";

import { ICuratedVerifier } from "./interfaces/ICuratedVerifier.sol";
import { IBaseModule, WithdrawnValidatorInfo } from "./interfaces/IBaseModule.sol";
import { ValidatorBalanceLimits } from "./lib/ValidatorBalanceLimits.sol";
import { gweiToWei } from "./Verifier.sol";

/// @notice A copy of `Verifier` for the Curated Module. Validators are reported as withdrawn once they reach their
///         withdrawable epoch, which supports both regular exits and outgoing consolidations. Withdrawal proofs are
///         not used, and the exit balance shortage is left to the committee.
contract CuratedVerifier is ICuratedVerifier, AccessControlEnumerable, PausableWithRoles {
    using SSZ for BeaconBlockHeader;
    using SSZ for Validator;

    // See `BEACON_ROOTS_ADDRESS` constant in the EIP-4788.
    address public constant BEACON_ROOTS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    uint64 public immutable SLOTS_PER_EPOCH;

    /// @dev Count of historical roots per accumulator.
    /// @dev See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
    uint64 public constant SLOTS_PER_HISTORICAL_ROOT = 8192;

    /// @dev This index is relative to a state like: `BeaconState.validators[0]`.
    GIndex public immutable GI_FIRST_VALIDATOR_PREV;

    /// @dev This index is relative to a state like: `BeaconState.validators[0]`.
    GIndex public immutable GI_FIRST_VALIDATOR_CURR;

    /// @dev This index is relative to a state like: `BeaconState.historical_summaries[0]`.
    GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_PREV;

    /// @dev This index is relative to a state like: `BeaconState.historical_summaries[0]`.
    GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_CURR;

    /// @dev This index is relative to HistoricalSummary like: HistoricalSummary.blockRoots[0].
    ///      Considered constant across forks.
    GIndex public constant GI_FIRST_BLOCK_ROOT_IN_SUMMARY =
        GIndex.wrap(0x000000000000000000000000000000000000000000000000000000000040000d);

    /// @dev This index is relative to a state like: `BeaconState.balances[0]`.
    GIndex public immutable GI_FIRST_BALANCES_NODE_PREV;

    /// @dev This index is relative to a state like: `BeaconState.balances[0]`.
    GIndex public immutable GI_FIRST_BALANCES_NODE_CURR;

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
        if (firstSupportedSlot > pivotSlot) revert InvalidPivotSlot();
        if (capellaSlot > firstSupportedSlot) revert InvalidCapellaSlot();

        WITHDRAWAL_ADDRESS = withdrawalAddress;
        MODULE = IBaseModule(module);

        SLOTS_PER_EPOCH = slotsPerEpoch;

        GI_FIRST_VALIDATOR_PREV = gindices.gIFirstValidatorPrev;
        GI_FIRST_VALIDATOR_CURR = gindices.gIFirstValidatorCurr;

        GI_FIRST_HISTORICAL_SUMMARY_PREV = gindices.gIFirstHistoricalSummaryPrev;
        GI_FIRST_HISTORICAL_SUMMARY_CURR = gindices.gIFirstHistoricalSummaryCurr;

        GI_FIRST_BALANCES_NODE_PREV = gindices.gIFirstBalanceNodePrev;
        GI_FIRST_BALANCES_NODE_CURR = gindices.gIFirstBalanceNodeCurr;

        FIRST_SUPPORTED_SLOT = firstSupportedSlot;
        PIVOT_SLOT = pivotSlot;
        CAPELLA_SLOT = capellaSlot;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc ICuratedVerifier
    function processSlashedProof(ProcessSlashedInput calldata data) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) revert UnsupportedSlot(data.recentBlock.header.slot);

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        if (!data.validator.object.slashed) revert ValidatorIsNotSlashed();

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.validator.nodeOperatorId, data.validator.keyIndex, 1);

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) revert InvalidPublicKey();
        }

        SSZ.verifyProof({
            proof: data.validator.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.validator.object.hashTreeRoot(),
            gI: _getValidatorGI(data.validator.index, data.recentBlock.header.slot)
        });

        MODULE.reportValidatorSlashing(data.validator.nodeOperatorId, data.validator.keyIndex);
    }

    /// @inheritdoc ICuratedVerifier
    function processWithdrawnProof(ProcessWithdrawnInput calldata data) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) revert UnsupportedSlot(data.recentBlock.header.slot);

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        if (address(uint160(uint256(data.validator.object.withdrawalCredentials))) != WITHDRAWAL_ADDRESS) {
            revert InvalidWithdrawalAddress();
        }

        if (data.validator.object.slashed) revert ValidatorIsSlashed();
        if (_computeEpochAtSlot(data.recentBlock.header.slot) < data.validator.object.withdrawableEpoch) {
            revert ValidatorIsNotWithdrawable();
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(data.validator.nodeOperatorId, data.validator.keyIndex, 1);

            if (keccak256(pubkey) != keccak256(data.validator.object.pubkey)) revert InvalidPublicKey();
        }

        SSZ.verifyProof({
            proof: data.validator.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.validator.object.hashTreeRoot(),
            gI: _getValidatorGI(data.validator.index, data.recentBlock.header.slot)
        });

        uint256[] memory confirmedBalances = MODULE.getKeyConfirmedBalances(
            data.validator.nodeOperatorId,
            data.validator.keyIndex,
            1
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: data.validator.nodeOperatorId,
            keyIndex: data.validator.keyIndex,
            // The module charges the exit balance shortage below the confirmed balance. Reporting the confirmed balance
            // as the exit balance leaves the shortage, if any, to the committee.
            exitBalance: confirmedBalances[0] + ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        MODULE.reportRegularWithdrawnValidators(validatorInfos);
    }

    /// @inheritdoc ICuratedVerifier
    function processBalanceProof(ProcessBalanceProofInput calldata data) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.recentBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        uint64 balanceGwei = _processBalanceProof(
            data.validator,
            data.balance,
            data.recentBlock.header.stateRoot,
            data.recentBlock.header.slot
        );

        MODULE.reportValidatorBalance(data.validator.nodeOperatorId, data.validator.keyIndex, gweiToWei(balanceGwei));
    }

    /// @inheritdoc ICuratedVerifier
    function processHistoricalBalanceProof(ProcessHistoricalBalanceProofInput calldata data) external whenResumed {
        if (data.recentBlock.header.slot < FIRST_SUPPORTED_SLOT) revert UnsupportedSlot(data.recentBlock.header.slot);
        if (data.historicalBlock.header.slot < FIRST_SUPPORTED_SLOT) {
            revert UnsupportedSlot(data.historicalBlock.header.slot);
        }

        {
            bytes32 trustedHeaderRoot = _getParentBlockRoot(data.recentBlock.rootsTimestamp);
            if (trustedHeaderRoot != data.recentBlock.header.hashTreeRoot()) revert InvalidBlockHeader();
        }

        SSZ.verifyProof({
            proof: data.historicalBlock.proof,
            root: data.recentBlock.header.stateRoot,
            leaf: data.historicalBlock.header.hashTreeRoot(),
            gI: _getHistoricalBlockRootGI(data.recentBlock.header.slot, data.historicalBlock.header.slot)
        });

        uint64 balanceGwei = _processBalanceProof(
            data.validator,
            data.balance,
            data.historicalBlock.header.stateRoot,
            data.historicalBlock.header.slot
        );

        MODULE.reportValidatorBalance(data.validator.nodeOperatorId, data.validator.keyIndex, gweiToWei(balanceGwei));
    }

    function _getParentBlockRoot(uint64 blockTimestamp) internal view returns (bytes32) {
        (bool success, bytes memory data) = BEACON_ROOTS.staticcall(abi.encode(blockTimestamp));

        if (!success || data.length == 0) revert RootNotFound();

        return abi.decode(data, (bytes32));
    }

    function _processBalanceProof(
        ValidatorWitness calldata validator,
        BalanceWitness calldata balance,
        bytes32 stateRoot,
        Slot stateSlot
    ) internal view returns (uint64 balanceGwei) {
        if (_computeEpochAtSlot(stateSlot) >= validator.object.withdrawableEpoch) {
            revert ValidatorIsWithdrawable();
        }

        {
            bytes memory pubkey = MODULE.getSigningKeys(validator.nodeOperatorId, validator.keyIndex, 1);
            if (keccak256(pubkey) != keccak256(validator.object.pubkey)) revert InvalidPublicKey();
        }

        SSZ.verifyProof({
            proof: validator.proof,
            root: stateRoot,
            leaf: validator.object.hashTreeRoot(),
            gI: _getValidatorGI(validator.index, stateSlot)
        });

        balanceGwei = _verifyValidatorBalance({
            validatorIndex: validator.index,
            balanceNode: balance.node,
            stateRoot: stateRoot,
            stateSlot: stateSlot,
            proof: balance.proof
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

    function _getValidatorBalanceGI(uint256 offset, Slot stateSlot) internal view returns (GIndex) {
        GIndex gI = stateSlot < PIVOT_SLOT ? GI_FIRST_BALANCES_NODE_PREV : GI_FIRST_BALANCES_NODE_CURR;
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
        gI = gI.concat(GI_FIRST_BLOCK_ROOT_IN_SUMMARY); // historicalSummaries[summaryIndex].blockRoots[0]
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
