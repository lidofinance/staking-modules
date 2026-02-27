// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";
import { StakingRouterIntegrationTestBase } from "../common/StakingRouter.t.sol";
import { NodeOperator } from "src/interfaces/IBaseModule.sol";

contract StakingRouterIntegrationTestCSM is StakingRouterIntegrationTestBase, CSMIntegrationBase {
    function setUp() public override {
        super.setUp();
        if (!isStakingRouterUpgraded) {
            // Skip: this suite validates router-v2 deposit behavior unavailable on legacy core/router versions.
            vm.skip(true, "Suite requires upgraded staking router version for router-v2 deposit behavior");
        }

        _maximizeModuleShare(moduleId);
        _disableDepositsForOtherModules(moduleId);
        hugeDeposit();
        _ensureStakingRouterCanDeposit(moduleId);
    }

    function test_routerDeposit_happyPath_callsObtainDepositDataAndUsesReturnedCount() public assertInvariants {
        (uint256 noId, ) = integrationHelpers.getDepositableNodeOperator(nextAddress());
        NodeOperator memory noBefore = module.getNodeOperator(noId);
        assertGt(noBefore.depositableValidatorsCount, 0);

        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();

        uint256 requestedDeposits = _getExpectedRouterDepositRequestCount();
        assertGt(requestedDeposits, 0);
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(module.obtainDepositData.selector, requestedDeposits, "")
        );
        vm.prank(locator.depositSecurityModule());
        stakingRouter.deposit(moduleId, "");

        (, uint256 depositedAfter, ) = module.getStakingModuleSummary();
        uint256 actualDeposits = depositedAfter - depositedBefore;
        assertEq(depositedAfter - depositedBefore, actualDeposits);
        assertEq(actualDeposits, requestedDeposits);

        NodeOperator memory noAfter = module.getNodeOperator(noId);
        uint256 depositedDelta = noAfter.totalDepositedKeys - noBefore.totalDepositedKeys;
        uint256 depositableDelta = noBefore.depositableValidatorsCount - noAfter.depositableValidatorsCount;
        assertGt(depositedDelta, 0);
        assertEq(depositedDelta, depositableDelta);
    }
}
