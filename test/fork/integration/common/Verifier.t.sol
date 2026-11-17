// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CuratedVerifier } from "../../../../src/CuratedVerifier.sol";
import { ValidatorBalanceLimits } from "../../../../src/lib/ValidatorBalanceLimits.sol";

import { CuratedVerifierProofs } from "../../../helpers/CuratedVerifierProofs.sol";
import { VerifierProofs } from "../../../helpers/VerifierProofs.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract VerifierIntegrationTestBase is ModuleTypeBase {
    function setUp() public {
        _setUpModule();
    }

    function test_processSlashedProof() public {
        uint256 noId = integrationHelpers.addDepositedNodeOperator(nextAddress(), 1);

        _processSlashedProof(noId, 0);

        assertTrue(module.isValidatorSlashed(noId, 0));
    }

    function test_processWithdrawalProof() public {
        uint256 noId = integrationHelpers.addDepositedNodeOperator(nextAddress(), 1);

        _processWithdrawalProof(noId, 0);

        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1, "withdrawn keys");
    }

    function _processSlashedProof(uint256 noId, uint256 keyIndex) internal virtual {
        verifier.processSlashedProof(VerifierProofs.slashedProof(verifier, noId, keyIndex));
    }

    function _processWithdrawalProof(uint256 noId, uint256 keyIndex) internal virtual {
        verifier.processWithdrawalProof(
            VerifierProofs.withdrawalProof(verifier, noId, keyIndex, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE)
        );
    }
}

/// @dev Modules accept balance proofs only for 0x02 validators.
abstract contract VerifierBalanceIntegrationTestBase is VerifierIntegrationTestBase {
    function test_processBalanceProof() public {
        uint256 noId = integrationHelpers.addDepositedNodeOperator(nextAddress(), 1);
        uint256 operatorBalanceBefore = module.getNodeOperatorBalance(noId);
        // Modules confirm the key balance above the activation balance.
        uint256 confirmed = 8 ether;
        uint256 balance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + confirmed;

        _processBalanceProof(noId, 0, balance);

        assertEq(module.getKeyConfirmedBalances(noId, 0, 1)[0], confirmed, "key confirmed balance");
        assertEq(module.getKeyAllocatedBalances(noId, 0, 1)[0], confirmed, "key allocated balance");
        assertEq(module.getNodeOperatorBalance(noId) - operatorBalanceBefore, confirmed, "operator balance");
    }

    function _processBalanceProof(uint256 noId, uint256 keyIndex, uint256 balance) internal virtual {
        verifier.processBalanceProof(VerifierProofs.balanceProof(verifier, noId, keyIndex, balance));
    }
}

contract VerifierIntegrationTestCSM is VerifierIntegrationTestBase, CSMIntegrationBase {}

contract VerifierIntegrationTestCSM0x02 is VerifierBalanceIntegrationTestBase, CSM0x02IntegrationBase {}

/// @dev `CuratedVerifier` has its own interface until the verifiers are unified in phase 2.
contract VerifierIntegrationTestCurated is VerifierBalanceIntegrationTestBase, CuratedIntegrationBase {
    function _processSlashedProof(uint256 noId, uint256 keyIndex) internal override {
        CuratedVerifier curatedVerifier = CuratedVerifier(address(verifier));
        curatedVerifier.processSlashedProof(CuratedVerifierProofs.slashedProof(curatedVerifier, noId, keyIndex));
    }

    /// @dev `CuratedVerifier` proves that the validator has reached the withdrawable epoch, not the withdrawal itself.
    function _processWithdrawalProof(uint256 noId, uint256 keyIndex) internal override {
        CuratedVerifier curatedVerifier = CuratedVerifier(address(verifier));
        curatedVerifier.processWithdrawnProof(CuratedVerifierProofs.withdrawnProof(curatedVerifier, noId, keyIndex));
    }

    function _processBalanceProof(uint256 noId, uint256 keyIndex, uint256 balance) internal override {
        CuratedVerifier curatedVerifier = CuratedVerifier(address(verifier));
        curatedVerifier.processBalanceProof(
            CuratedVerifierProofs.balanceProof(curatedVerifier, noId, keyIndex, balance)
        );
    }
}
