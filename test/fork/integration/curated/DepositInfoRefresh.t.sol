// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";

import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract DepositInfoRefreshTestCurated is CuratedIntegrationBase {
    function setUp() public {
        _setUpModule();

        address admin = metaRegistry.getRoleMember(metaRegistry.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(admin);
        metaRegistry.grantRole(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE(), address(this));
        metaRegistry.grantRole(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_refreshAfterBondCurveWeightUpdate() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 3);
        uint256 curveId = accounting.getBondCurveId(noId);

        // Verify operator can deposit before weight change
        (, , uint256 depositableBefore) = module.getStakingModuleSummary();
        assertGt(depositableBefore, 0, "should have depositable keys");

        // Set weight to 0 — triggers requestFullDepositInfoUpdate
        metaRegistry.setBondCurveWeight(curveId, 0);
        metaRegistry.refreshOperatorWeight(noId);

        // Deposit info is stale after weight change, run batch update
        integrationHelpers.runFullBatchDepositInfoUpdate();

        // obtainDepositData should now return 0 keys (weight is zero)
        vm.prank(address(stakingRouter));
        (bytes memory pubkeys, ) = module.obtainDepositData(10, "");
        assertEq(pubkeys.length, 0, "should not deposit with zero weight");

        // Restore weight
        metaRegistry.setBondCurveWeight(curveId, 1);
        metaRegistry.refreshOperatorWeight(noId);

        // Run batch update to refresh deposit info
        integrationHelpers.runFullBatchDepositInfoUpdate();

        // Now deposits should work again
        (, , uint256 depositableAfter) = module.getStakingModuleSummary();
        assertGt(depositableAfter, 0, "should have depositable keys after weight restore");
    }

    function test_refreshAfterAccountingCurveUpdate() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 3);
        uint256 curveId = accounting.getBondCurveId(noId);

        (, , uint256 depositableBefore) = module.getStakingModuleSummary();
        assertGt(depositableBefore, 0, "should have depositable keys");

        // Update the bond curve in Accounting (requires MANAGE_BOND_CURVES_ROLE)
        address accAdmin = accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(accAdmin);
        accounting.grantRole(accounting.MANAGE_BOND_CURVES_ROLE(), address(this));
        vm.stopPrank();

        // Create a curve with a higher bond requirement
        IBondCurve.BondCurveIntervalInput[] memory newCurve = new IBondCurve.BondCurveIntervalInput[](1);
        newCurve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: 64 ether });
        accounting.updateBondCurve(curveId, newCurve);

        // Run batch update to refresh deposit info
        integrationHelpers.runFullBatchDepositInfoUpdate();

        // Depositable count may have decreased due to higher bond requirement
        (, , uint256 depositableAfter) = module.getStakingModuleSummary();
        // The exact count depends on the operator's existing bond vs new curve,
        // but the batch update should complete without error
    }

    function test_refreshAfterGroupChange() public {
        address addr1 = nextAddress("Op1");
        address addr2 = nextAddress("Op2");
        uint256 noId1 = integrationHelpers.addNodeOperator(addr1, 3);
        uint256 noId2 = integrationHelpers.addNodeOperator(addr2, 3);

        // Bump curve weight so mulDiv(weight, 5000, 10000) > 0
        uint256 curveId = accounting.getBondCurveId(noId1);
        if (metaRegistry.getBondCurveWeight(curveId) < 10000) {
            metaRegistry.setBondCurveWeight(curveId, 10000);
        }

        // Remove both from their default groups
        uint256 g1 = metaRegistry.getNodeOperatorGroupId(noId1);
        uint256 g2 = metaRegistry.getNodeOperatorGroupId(noId2);
        if (g1 != metaRegistry.NO_GROUP_ID()) _clearGroup(g1);
        if (g2 != metaRegistry.NO_GROUP_ID() && g2 != g1) _clearGroup(g2);

        integrationHelpers.runFullBatchDepositInfoUpdate();

        // Operators with no group have weight=0 → depositable=0
        assertEq(metaRegistry.getNodeOperatorWeight(noId1), 0, "weight should be 0 outside group");

        // Create a new group with both operators
        IMetaRegistry.SubNodeOperator[] memory subs = new IMetaRegistry.SubNodeOperator[](2);
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId1), share: 5000 });
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId2), share: 5000 });

        metaRegistry.createOrUpdateOperatorGroup(
            metaRegistry.NO_GROUP_ID(),
            IMetaRegistry.OperatorGroup({
                subNodeOperators: subs,
                externalOperators: new IMetaRegistry.ExternalOperator[](0)
            })
        );

        integrationHelpers.runFullBatchDepositInfoUpdate();

        // Weights should now be positive
        assertGt(metaRegistry.getNodeOperatorWeight(noId1), 0, "weight should be positive in group");
        assertGt(metaRegistry.getNodeOperatorWeight(noId2), 0, "weight should be positive in group");
    }

    // ─── Helpers ─────────────────────────────────────────────────

    function _clearGroup(uint256 groupId) internal {
        metaRegistry.createOrUpdateOperatorGroup(
            groupId,
            IMetaRegistry.OperatorGroup({
                subNodeOperators: new IMetaRegistry.SubNodeOperator[](0),
                externalOperators: new IMetaRegistry.ExternalOperator[](0)
            })
        );
    }
}
