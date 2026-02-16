// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleIncomingConsolidation is ModuleFixtures {
    function test_reportIncomingConsolidation_HappyPath() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAddedBalanceChanged(noId, 0, 10 ether);
        vm.expectEmit(address(module));
        emit IBaseModule.IncomingConsolidationReported(noId, 0, 42, 10 ether);
        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 10 ether
        });

        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);
    }

    function test_reportIncomingConsolidation_RevertWhen_Replay() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 10 ether
        });

        vm.expectRevert(IBaseModule.ConsolidationAlreadyReported.selector);
        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 5 ether
        });
    }

    function test_reportIncomingConsolidation_DifferentSourceValidators() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 10 ether
        });
        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 43,
            amount: 5 ether
        });

        assertEq(module.getKeyAddedBalance(noId, 0), 15 ether);
    }

    function test_reportIncomingConsolidation_incrementsNonce() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 nonceBefore = module.getNonce();

        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 10 ether
        });

        assertEq(module.getNonce(), nonceBefore + 1);
    }

    function test_reportIncomingConsolidation_RevertWhen_NoRole() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        bytes32 role = module.VERIFIER_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 1 ether
        });
    }

    function test_reportIncomingConsolidation_RevertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator();

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 1 ether
        });
    }

    function test_reportIncomingConsolidation_allowsAfterWithdrawal() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        module.reportRegularWithdrawnValidators(validatorInfos);

        module.reportIncomingConsolidation({
            nodeOperatorId: noId,
            keyIndex: 0,
            sourceValidatorIndex: 42,
            amount: 1 ether
        });
        assertEq(module.getKeyAddedBalance(noId, 0), 1 ether);
    }
}
