// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleKeyAddedBalance is ModuleFixtures {
    function test_getKeyAddedBalance_defaultZero() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        assertEq(module.getKeyAddedBalance(noId, 0), 0);
    }

    function test_getKeyAddedBalance_afterSet() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        setKeyAddedBalance(noId, 0, 3 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 3 ether);
    }
}

abstract contract ModuleSyncKeyAddedBalance is ModuleFixtures {
    function test_syncKeyAddedBalance_happyPath() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceWei = WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether;

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAddedBalanceChanged(noId, 0, 10 ether);
        module.syncKeyAddedBalance(noId, 0, balanceWei);

        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);
    }

    function test_syncKeyAddedBalance_increasesWhenHigher() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 5 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 5 ether);

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAddedBalanceChanged(noId, 0, 10 ether);
        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);
    }

    function test_syncKeyAddedBalance_doesNotDecrease() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);

        // Lower value — should not change
        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 5 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);

        // Equal value — should not change
        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 10 ether);
    }

    function test_syncKeyAddedBalance_capsAtMax() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 cap = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE - WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;
        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE + 100 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), cap);
    }

    function test_syncKeyAddedBalance_noUpdateWhenBelowMinActivation() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE);
        assertEq(module.getKeyAddedBalance(noId, 0), 0);

        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE - 1 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 0);
    }

    function test_syncKeyAddedBalance_revertWhen_NoRole() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.prank(stranger);
        vm.expectRevert();
        module.syncKeyAddedBalance(noId, 0, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 1 ether);
    }

    function test_syncKeyAddedBalance_revertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.syncKeyAddedBalance(noId, 1, WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE + 1 ether);
    }
}
