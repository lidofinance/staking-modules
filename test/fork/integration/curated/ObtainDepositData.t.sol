// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { CuratedDepositAllocator } from "src/lib/allocator/CuratedDepositAllocator.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract ObtainDepositDataTestCurated is CuratedIntegrationBase {
    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_obtainDepositData_increasesOperatorBalance() public assertInvariants {
        uint256 keysCount = 2;
        uint256 operatorsBefore = module.getNodeOperatorsCount();
        uint256 noId = integrationHelpers.addNodeOperator(nextAddress(), keysCount);

        ICuratedModule curatedModule = ICuratedModule(address(module));
        uint256 balanceBefore = curatedModule.getNodeOperatorBalance(noId);

        (, uint256 totalDepositedBefore, uint256 depositableBefore) = module.getStakingModuleSummary();

        uint256 request = depositableBefore > keysCount ? keysCount : depositableBefore;

        vm.prank(address(stakingRouter));
        (bytes memory pubkeys, bytes memory signatures) = module.obtainDepositData(request, "");

        uint256 allocated = pubkeys.length / 48;
        assertEq(pubkeys.length, allocated * 48);
        assertEq(signatures.length, allocated * 96);

        (, uint256 totalDepositedAfter, uint256 depositableAfter) = module.getStakingModuleSummary();
        assertEq(totalDepositedAfter, totalDepositedBefore + allocated);
        assertEq(depositableAfter, depositableBefore - allocated);

        uint256 balanceAfter = curatedModule.getNodeOperatorBalance(noId);
        assertEq(balanceAfter, balanceBefore + allocated * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }
}
