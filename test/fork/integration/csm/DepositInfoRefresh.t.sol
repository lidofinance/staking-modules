// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";

import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract DepositInfoRefreshTestCSM is CSMIntegrationBase {
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 5;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        assertModuleEnqueuedCount(module);
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

        vm.startPrank(accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0));
        accounting.grantRole(accounting.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        nodeOperator = nextAddress("NodeOperator");
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
    }

    function test_depositInfoRefreshPipeline() public assertInvariants {
        ICSModule csm = ICSModule(address(module));
        uint256 curveId = accounting.getBondCurveId(defaultNoId);
        // Update bond curve to trigger full deposit info refresh
        IBondCurve.BondCurveData memory curveData = accounting.getBondCurve(defaultNoId);
        IBondCurve.BondCurveIntervalInput[] memory newCurve = new IBondCurve.BondCurveIntervalInput[](
            curveData.intervals.length
        );
        for (uint256 i; i < curveData.intervals.length; ++i) {
            newCurve[i] = IBondCurve.BondCurveIntervalInput({
                minKeysCount: curveData.intervals[i].minKeysCount,
                trend: curveData.intervals[i].trend
            });
        }

        bytes32 manageCurvesRole = accounting.MANAGE_BOND_CURVES_ROLE();
        accounting.grantRole(manageCurvesRole, address(this));
        accounting.updateBondCurve(curveId, newCurve);

        // Deposit info is now stale
        uint256 toUpdate = module.getNodeOperatorDepositInfoToUpdateCount();
        assertTrue(toUpdate > 0, "Deposit info should need update after curve change");

        // cleanDepositQueue should revert while deposit info is stale
        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        csm.cleanDepositQueue(1);

        integrationHelpers.runFullBatchDepositInfoUpdate();

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 0, "All operators should be updated");

        // cleanDepositQueue should now succeed
        csm.cleanDepositQueue(1);
    }
}
