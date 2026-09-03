// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleGetKeyAllocatedBalances is ModuleFixtures {
    function test_getKeyAllocatedBalances_defaultZero() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        assertEq(module.getKeyAllocatedBalances(noId, 0, 2), UintArr(0, 0));
    }

    function test_getKeyAllocatedBalances_batch() public {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        module.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 3 ether, 1);
        module.reportValidatorBalance(noId, 1, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 5 ether, 1);

        assertEq(module.getKeyAllocatedBalances(noId, 0, 2), UintArr(3 ether, 5 ether));
        assertEq(module.getKeyAllocatedBalances(noId, 1, 1), UintArr(5 ether));
    }

    function test_getKeyAllocatedBalances_revertWhen_InvalidOffset() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getKeyAllocatedBalances(noId, 1, 1);
    }
}
