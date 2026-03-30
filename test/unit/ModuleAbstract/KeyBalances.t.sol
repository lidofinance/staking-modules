// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleKeyAllocatedBalance is ModuleFixtures {
    function test_getKeyAllocatedBalance_defaultZero() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        assertEq(module.getKeyAllocatedBalances(noId, 0, 2), UintArr(0, 0));
    }

    function test_getKeyAllocatedBalance_batch() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 3 ether);
        module.reportValidatorBalance(noId, 1, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 5 ether);

        assertEq(module.getKeyAllocatedBalances(noId, 0, 2), UintArr(3 ether, 5 ether));
        assertEq(module.getKeyAllocatedBalances(noId, 1, 1), UintArr(5 ether));
    }

    function test_getKeyAllocatedBalance_revertWhen_InvalidOffset() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getKeyAllocatedBalances(noId, 1, 1);
    }

    function test_getKeyConfirmedBalance_zeroOnDeposit() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        assertEq(module.getKeyConfirmedBalances(noId, 0, 2), UintArr(0, 0));
    }

    function test_getKeyConfirmedBalance_afterReport() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 3 ether);
        module.reportValidatorBalance(noId, 1, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 5 ether);
        assertEq(module.getKeyConfirmedBalances(noId, 0, 2), UintArr(3 ether, 5 ether));
        assertEq(module.getKeyConfirmedBalances(noId, 1, 1), UintArr(5 ether));
        uint256 balanceWei = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * 2 + 8 ether;
        assertEq(module.getTotalModuleStake(), balanceWei);
        assertEq(module.getNodeOperatorBalance(noId), balanceWei);
    }
}

abstract contract ModuleReportValidatorBalance is ModuleFixtures {
    function test_reportValidatorBalance_happyPath() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether;

        vm.expectEmit(address(module));
        emit IBaseModule.KeyConfirmedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, balanceWei);

        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(10 ether));
        assertEq(module.getTotalModuleStake(), balanceWei);
        assertEq(module.getNodeOperatorBalance(noId), balanceWei);
    }

    function test_reportValidatorBalance_increasesWhenHigher() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 firstBalance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 5 ether;
        uint256 secondBalance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether;

        module.reportValidatorBalance(noId, 0, firstBalance);
        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(5 ether));

        vm.expectEmit(address(module));
        emit IBaseModule.KeyConfirmedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, secondBalance);
        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(10 ether));
        assertEq(module.getTotalModuleStake(), secondBalance);
        assertEq(module.getNodeOperatorBalance(noId), secondBalance);
    }

    function test_reportValidatorBalance_doesNotDecrease() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether;
        module.reportValidatorBalance(noId, 0, balanceWei);
        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(10 ether));

        // Lower value — should revert
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 5 ether);

        // Equal value — should revert
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, balanceWei);

        assertEq(module.getTotalModuleStake(), balanceWei);
        assertEq(module.getNodeOperatorBalance(noId), balanceWei);
    }

    function test_reportValidatorBalance_capsAtMax() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE + 100 ether);
        assertEq(
            module.getKeyConfirmedBalances(noId, 0, 1),
            UintArr(ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE)
        );
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
    }

    function test_reportValidatorBalance_updatesKeyAllocatedBalance() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAllocatedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getKeyAllocatedBalances(noId, 0, 1), UintArr(10 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
    }

    function test_reportValidatorBalance_revertWhen_confirmedBalanceIsZero() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // Reporting MIN_ACTIVATION_BALANCE results in zero added balance, which is <= stored zero.
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_reportValidatorBalance_revertWhen_belowMinActivation() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - 1 ether);
    }

    function test_reportValidatorBalance_revertWhen_validatorWithdrawn() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
    }

    function test_reportValidatorBalance_revertWhen_NoRole() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.prank(stranger);
        vm.expectRevert();
        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 1 ether);
    }

    function test_reportValidatorBalance_revertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportValidatorBalance(noId, 1, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 1 ether);
    }

    function test_reportValidatorBalance_revertWhen_NoNodeOperator() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorBalance(0, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 1 ether);
    }
}
