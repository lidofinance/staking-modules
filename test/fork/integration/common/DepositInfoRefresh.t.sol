// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";

import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase } from "./ModuleTypeBase.sol";

abstract contract DepositInfoRefreshTestBase is ModuleTypeBase {
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 5;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public virtual {
        _setUpModule();

        address moduleAdmin = module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0);
        bytes32 moduleAdminRole = module.DEFAULT_ADMIN_ROLE();
        vm.prank(moduleAdmin);
        module.grantRole(moduleAdminRole, address(this));

        address accountingAdmin = accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0);
        bytes32 accountingAdminRole = accounting.DEFAULT_ADMIN_ROLE();
        vm.prank(accountingAdmin);
        accounting.grantRole(accountingAdminRole, address(this));

        handleStakingLimit();
        handleBunkerMode();

        nodeOperator = nextAddress("NodeOperator");
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
    }

    function test_depositInfoRefreshPipeline() public assertInvariants {
        ICSModule csm = ICSModule(address(module));
        uint256 curveId = accounting.getBondCurveId(defaultNoId);
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

        uint256 toUpdate = module.getNodeOperatorDepositInfoToUpdateCount();
        assertGt(toUpdate, 0, "deposit info should need update after curve change");

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        csm.cleanDepositQueue(1);

        integrationHelpers.runFullBatchDepositInfoUpdate();

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 0, "all operators should be updated");
        csm.cleanDepositQueue(1);
    }
}

contract DepositInfoRefreshTestCSM is DepositInfoRefreshTestBase, CSMIntegrationBase {}

contract DepositInfoRefreshTestCSM0x02 is DepositInfoRefreshTestBase, CSM0x02IntegrationBase {}
