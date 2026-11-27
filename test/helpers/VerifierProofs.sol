// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Verifier } from "src/Verifier.sol";
import { IVerifier } from "src/interfaces/IVerifier.sol";
import { BeaconBlockHeader } from "src/lib/Types.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { BeaconProofs } from "./BeaconProofs.sol";

/// @notice Proof inputs for the `Verifier` deployed on a fork, see `BeaconProofs`.
///         `CuratedVerifierProofs` does the same for `CuratedVerifier`.
library VerifierProofs {
    /// @dev Returns a proof of slashing of the key at `keyIndex` of `noId`.
    function slashedProof(
        Verifier verifier,
        uint256 noId,
        uint256 keyIndex
    ) internal returns (IVerifier.ProcessSlashedInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            status: BeaconProofs.ValidatorStatus.Slashed
        });
        BeaconProofs.mockBeaconRoot(proof.blockRoot);

        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.recentBlock = _recentBlock(proof.header);
    }

    /// @dev Returns a proof of `balance` for the key at `keyIndex` of `noId`.
    function balanceProof(
        Verifier verifier,
        uint256 noId,
        uint256 keyIndex,
        uint256 balance
    ) internal returns (IVerifier.ProcessBalanceProofInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: balance,
            status: BeaconProofs.ValidatorStatus.Active
        });
        BeaconProofs.mockBeaconRoot(proof.nextBlockRoot);

        input.recentBlock = _recentBlock(proof.nextHeader);
        input.balanceBlock = IVerifier.HistoricalHeaderWitness({ header: proof.header, proof: proof.blockRootProof });
        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.balance = IVerifier.BalanceWitness({ node: proof.balanceNode, proof: proof.balanceProof });
    }

    /// @dev Returns a proof of a full withdrawal of `amount` for the key at `keyIndex` of `noId`.
    function withdrawalProof(
        Verifier verifier,
        uint256 noId,
        uint256 keyIndex,
        uint256 amount
    ) internal returns (IVerifier.ProcessWithdrawalInput memory input) {
        BeaconProofs.ValidatorProof memory proof = _validatorProof({
            verifier: verifier,
            noId: noId,
            keyIndex: keyIndex,
            balance: amount,
            status: BeaconProofs.ValidatorStatus.Withdrawn
        });
        BeaconProofs.mockBeaconRoot(proof.nextBlockRoot);

        input.withdrawal = IVerifier.WithdrawalWitness({
            offset: proof.withdrawalOffset,
            object: proof.withdrawal,
            proof: proof.withdrawalProof
        });
        input.validator = _validatorWitness(proof, noId, keyIndex);
        input.recentBlock = _recentBlock(proof.nextHeader);
        input.withdrawalBlock = IVerifier.HistoricalHeaderWitness({
            header: proof.header,
            proof: proof.blockRootProof
        });
    }

    function _validatorProof(
        Verifier verifier,
        uint256 noId,
        uint256 keyIndex,
        uint256 balance,
        BeaconProofs.ValidatorStatus status
    ) private returns (BeaconProofs.ValidatorProof memory) {
        return
            BeaconProofs.getValidatorProof({
                pubkey: verifier.MODULE().getSigningKeys(noId, keyIndex, 1),
                withdrawalCredentials: verifier.WITHDRAWAL_CREDENTIALS(),
                firstSupportedSlot: verifier.FIRST_SUPPORTED_SLOT(),
                gloasSlot: verifier.GLOAS_SLOT(),
                balance: balance,
                status: status
            });
    }

    function _validatorWitness(
        BeaconProofs.ValidatorProof memory proof,
        uint256 noId,
        uint256 keyIndex
    ) private pure returns (IVerifier.ValidatorWitness memory) {
        return
            IVerifier.ValidatorWitness({
                index: proof.validatorIndex,
                nodeOperatorId: uint32(noId),
                keyIndex: uint32(keyIndex),
                object: proof.validator,
                proof: proof.validatorProof
            });
    }

    function _recentBlock(BeaconBlockHeader memory header) private view returns (IVerifier.RecentHeaderWitness memory) {
        return IVerifier.RecentHeaderWitness({ header: header, rootsTimestamp: uint64(block.timestamp) });
    }
}
