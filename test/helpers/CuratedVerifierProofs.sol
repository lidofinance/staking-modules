// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CuratedVerifier } from "src/CuratedVerifier.sol";
import { ICuratedVerifier } from "src/interfaces/ICuratedVerifier.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { BeaconProofs } from "./BeaconProofs.sol";

/// @notice Proof inputs for the `CuratedVerifier` deployed on a fork, see `BeaconProofs`.
///         Slashed and balance proofs mirror `VerifierProofs`: the proofs match, but the verifiers have separate
///         interfaces until they are unified in phase 2.
library CuratedVerifierProofs {
    /// @dev Returns a proof of slashing of the key at `keyIndex` of `noId`.
    function slashedProof(
        CuratedVerifier verifier,
        uint256 noId,
        uint256 keyIndex
    ) internal returns (ICuratedVerifier.ProcessSlashedInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            status: BeaconProofs.ValidatorStatus.Slashed
        });

        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.recentBlock = _recentBlock(proof);
    }

    /// @dev Returns a proof of `balance` for the key at `keyIndex` of `noId`.
    function balanceProof(
        CuratedVerifier verifier,
        uint256 noId,
        uint256 keyIndex,
        uint256 balance
    ) internal returns (ICuratedVerifier.ProcessBalanceProofInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: balance,
            status: BeaconProofs.ValidatorStatus.Active
        });

        input.recentBlock = _recentBlock(proof);
        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.balance = ICuratedVerifier.BalanceWitness({ node: proof.balanceNode, proof: proof.balanceProof });
    }

    /// @dev Returns a proof that the key at `keyIndex` of `noId` has reached the withdrawable epoch.
    function withdrawnProof(
        CuratedVerifier verifier,
        uint256 noId,
        uint256 keyIndex
    ) internal returns (ICuratedVerifier.ProcessWithdrawnInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            status: BeaconProofs.ValidatorStatus.Withdrawn
        });

        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.recentBlock = _recentBlock(proof);
    }

    function _validatorProof(
        CuratedVerifier verifier,
        uint256 noId,
        uint256 keyIndex,
        uint256 balance,
        BeaconProofs.ValidatorStatus status
    ) private returns (BeaconProofs.ValidatorProof memory) {
        return
            BeaconProofs.mockBeaconRootAndGetValidatorProof({
                pubkey: verifier.MODULE().getSigningKeys(noId, keyIndex, 1),
                withdrawalAddress: verifier.WITHDRAWAL_ADDRESS(),
                // The current generalized indices apply from the pivot slot.
                slot: verifier.PIVOT_SLOT(),
                balance: balance,
                status: status
            });
    }

    function _validatorWitness(
        BeaconProofs.ValidatorProof memory proof,
        uint256 noId,
        uint256 keyIndex
    ) private pure returns (ICuratedVerifier.ValidatorWitness memory) {
        return
            ICuratedVerifier.ValidatorWitness({
                index: proof.validatorIndex,
                nodeOperatorId: uint32(noId),
                keyIndex: uint32(keyIndex),
                object: proof.validator,
                proof: proof.validatorProof
            });
    }

    function _recentBlock(
        BeaconProofs.ValidatorProof memory proof
    ) private view returns (ICuratedVerifier.RecentHeaderWitness memory) {
        return ICuratedVerifier.RecentHeaderWitness({ header: proof.header, rootsTimestamp: uint64(block.timestamp) });
    }
}
