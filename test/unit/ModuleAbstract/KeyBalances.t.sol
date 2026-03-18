// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleKeyAllocatedBalance is ModuleFixtures {
    function test_getKeyAllocatedBalance_defaultZero() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        assertEq(module.getKeyAllocatedBalance(noId, 0), 0);
    }

    function test_getKeyConfirmedBalance_zeroOnDeposit() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        assertEq(module.getKeyConfirmedBalance(noId, 0), 0);
    }

    function test_getKeyConfirmedBalance_afterReport() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 3 ether;
        module.reportValidatorBalance(noId, 0, balanceWei);
        assertEq(module.getKeyConfirmedBalance(noId, 0), 3 ether);
    }
}

abstract contract ModuleReportValidatorBalance is ModuleFixtures {
    function test_reportValidatorBalance_happyPath() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether;

        vm.expectEmit(address(module));
        emit IBaseModule.KeyConfirmedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, balanceWei);

        assertEq(module.getKeyConfirmedBalance(noId, 0), 10 ether);
    }

    function test_reportValidatorBalance_increasesWhenHigher() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 firstBalance = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 5 ether;
        uint256 secondBalance = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether;

        module.reportValidatorBalance(noId, 0, firstBalance);
        assertEq(module.getKeyConfirmedBalance(noId, 0), 5 ether);

        vm.expectEmit(address(module));
        emit IBaseModule.KeyConfirmedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, secondBalance);
        assertEq(module.getKeyConfirmedBalance(noId, 0), 10 ether);
    }

    function test_reportValidatorBalance_doesNotDecrease() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether;
        module.reportValidatorBalance(noId, 0, balanceWei);
        assertEq(module.getKeyConfirmedBalance(noId, 0), 10 ether);

        // Lower value — should revert
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 5 ether);

        // Equal value — should revert
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, balanceWei);
    }

    function test_reportValidatorBalance_capsAtMax() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE + 100 ether);
        assertEq(
            module.getKeyConfirmedBalance(noId, 0),
            WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE - WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE
        );
    }

    function test_reportValidatorBalance_updatesKeyAllocatedBalance() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAllocatedBalanceChanged(noId, 0, 10 ether);
        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getKeyAllocatedBalance(noId, 0), 10 ether);
    }

    function test_reportValidatorBalance_revertWhen_confirmedBalanceIsZero() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // Reporting MIN_ACTIVATION_BALANCE results in zero added balance, which is <= stored zero.
        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE);
    }

    function test_reportValidatorBalance_revertWhen_belowMinActivation() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.UnreportableBalance.selector);
        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE - 1 ether);
    }

    function test_reportValidatorBalance_revertWhen_NoRole() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.prank(stranger);
        vm.expectRevert();
        module.reportValidatorBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 1 ether);
    }

    function test_reportValidatorBalance_revertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportValidatorBalance(noId, 1, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 1 ether);
    }
}
