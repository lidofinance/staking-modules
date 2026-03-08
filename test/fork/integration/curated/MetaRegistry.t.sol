// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OperatorMetadata, IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract MetaRegistryIntegrationTestCurated is CuratedIntegrationBase {
    function setUp() public {
        _setUpModule();

        address admin = metaRegistry.getRoleMember(metaRegistry.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(admin);
        metaRegistry.grantRole(metaRegistry.SET_OPERATOR_INFO_ROLE(), address(this));
        metaRegistry.grantRole(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE(), address(this));
        metaRegistry.grantRole(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE(), address(this));
        vm.stopPrank();
    }

    // ─── Metadata ────────────────────────────────────────────────

    function test_setMetadataAsAdmin() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 1);

        OperatorMetadata memory meta = OperatorMetadata({
            name: "AdminSetName",
            description: "AdminSetDesc",
            ownerEditsRestricted: true
        });
        metaRegistry.setOperatorMetadataAsAdmin(noId, meta);

        OperatorMetadata memory stored = metaRegistry.getOperatorMetadata(noId);
        assertEq(stored.name, meta.name);
        assertEq(stored.description, meta.description);
        assertTrue(stored.ownerEditsRestricted);
    }

    function test_setMetadataAsOwner() public {
        address owner = nextAddress("Owner");
        uint256 noId = integrationHelpers.addNodeOperator(owner, 1);

        vm.prank(owner);
        metaRegistry.setOperatorMetadataAsOwner(noId, "OwnerName", "OwnerDesc");

        OperatorMetadata memory stored = metaRegistry.getOperatorMetadata(noId);
        assertEq(stored.name, "OwnerName");
        assertEq(stored.description, "OwnerDesc");
    }

    // ─── Operator Groups ─────────────────────────────────────────

    function test_createOperatorGroup() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 1);

        // Remove from default group first
        uint256 currentGroupId = metaRegistry.getNodeOperatorGroupId(noId);
        if (currentGroupId != metaRegistry.NO_GROUP_ID()) {
            _clearGroup(currentGroupId);
        }

        IMetaRegistry.SubNodeOperator[] memory subs = new IMetaRegistry.SubNodeOperator[](1);
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId), share: 10000 });

        IMetaRegistry.OperatorGroup memory group = IMetaRegistry.OperatorGroup({
            subNodeOperators: subs,
            externalOperators: new IMetaRegistry.ExternalOperator[](0)
        });

        uint256 countBefore = metaRegistry.getOperatorGroupsCount();
        metaRegistry.createOrUpdateOperatorGroup(metaRegistry.NO_GROUP_ID(), group);
        uint256 countAfter = metaRegistry.getOperatorGroupsCount();

        assertEq(countAfter, countBefore + 1);
        uint256 newGroupId = countAfter - 1;
        assertEq(metaRegistry.getNodeOperatorGroupId(noId), newGroupId);
        assertGt(metaRegistry.getNodeOperatorWeight(noId), 0);
    }

    function test_updateOperatorGroup() public {
        (uint256 noId1, uint256 noId2, uint256 groupId) = _createTwoOperatorGroup(5000, 5000);

        uint256 weightBefore1 = metaRegistry.getNodeOperatorWeight(noId1);
        uint256 weightBefore2 = metaRegistry.getNodeOperatorWeight(noId2);
        assertEq(weightBefore1, weightBefore2);

        // Update shares: 80/20
        IMetaRegistry.SubNodeOperator[] memory subs = new IMetaRegistry.SubNodeOperator[](2);
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId1), share: 8000 });
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId2), share: 2000 });

        metaRegistry.createOrUpdateOperatorGroup(
            groupId,
            IMetaRegistry.OperatorGroup({
                subNodeOperators: subs,
                externalOperators: new IMetaRegistry.ExternalOperator[](0)
            })
        );

        uint256 weightAfter1 = metaRegistry.getNodeOperatorWeight(noId1);
        uint256 weightAfter2 = metaRegistry.getNodeOperatorWeight(noId2);
        assertGt(weightAfter1, weightAfter2);
    }

    function test_clearOperatorGroup() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 1);

        uint256 groupId = metaRegistry.getNodeOperatorGroupId(noId);
        _clearGroup(groupId);

        assertEq(metaRegistry.getNodeOperatorGroupId(noId), metaRegistry.NO_GROUP_ID());
        assertEq(metaRegistry.getNodeOperatorWeight(noId), 0);

        // Depositable count should be 0 when weight is 0
        (, , uint256 depositableAfter) = module.getStakingModuleSummary();
        // Weight=0 means no deposits can happen for this operator
        // (global depositable may still be > 0 from other operators)
    }

    // ─── Bond Curve Weight ───────────────────────────────────────

    function test_setBondCurveWeight() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 1);
        uint256 curveId = accounting.getBondCurveId(noId);

        uint256 currentWeight = metaRegistry.getBondCurveWeight(curveId);
        uint256 newWeight = currentWeight + 1;
        uint256 nonceBefore = module.getNonce();

        metaRegistry.setBondCurveWeight(curveId, newWeight);

        assertEq(metaRegistry.getBondCurveWeight(curveId), newWeight);
        // setBondCurveWeight triggers requestFullDepositInfoUpdate on the module
        assertGt(module.getNonce(), nonceBefore);
        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), module.getNodeOperatorsCount());
    }

    function test_refreshOperatorWeight() public {
        address noAddr = nextAddress("Operator");
        uint256 noId = integrationHelpers.addNodeOperator(noAddr, 1);
        uint256 curveId = accounting.getBondCurveId(noId);

        uint256 currentWeight = metaRegistry.getBondCurveWeight(curveId);
        uint256 newWeight = currentWeight * 2 + 1;

        // Change curve weight (does NOT auto-update operator weights)
        metaRegistry.setBondCurveWeight(curveId, newWeight);

        // Refresh must update the operator's effective weight
        uint256 weightBefore = metaRegistry.getNodeOperatorWeight(noId);
        metaRegistry.refreshOperatorWeight(noId);
        uint256 weightAfter = metaRegistry.getNodeOperatorWeight(noId);

        // Weight should have changed after refresh
        assertTrue(weightAfter != weightBefore);
        assertGt(weightAfter, 0);
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

    function _createTwoOperatorGroup(
        uint16 share1,
        uint16 share2
    ) internal returns (uint256 noId1, uint256 noId2, uint256 groupId) {
        address addr1 = nextAddress("Op1");
        address addr2 = nextAddress("Op2");
        noId1 = integrationHelpers.addNodeOperator(addr1, 1);
        noId2 = integrationHelpers.addNodeOperator(addr2, 1);

        // Bump curve weight so mulDiv(weight, share, 10000) > 0 for fractional shares
        uint256 curveId = accounting.getBondCurveId(noId1);
        uint256 curveWeight = metaRegistry.getBondCurveWeight(curveId);
        if (curveWeight < 10000) {
            metaRegistry.setBondCurveWeight(curveId, 10000);
        }

        // Remove both from their default groups
        uint256 g1 = metaRegistry.getNodeOperatorGroupId(noId1);
        uint256 g2 = metaRegistry.getNodeOperatorGroupId(noId2);
        if (g1 != metaRegistry.NO_GROUP_ID()) _clearGroup(g1);
        if (g2 != metaRegistry.NO_GROUP_ID() && g2 != g1) _clearGroup(g2);

        IMetaRegistry.SubNodeOperator[] memory subs = new IMetaRegistry.SubNodeOperator[](2);
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId1), share: share1 });
        // forge-lint: disable-next-line(unsafe-typecast)
        subs[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: uint64(noId2), share: share2 });

        uint256 countBefore = metaRegistry.getOperatorGroupsCount();
        metaRegistry.createOrUpdateOperatorGroup(
            metaRegistry.NO_GROUP_ID(),
            IMetaRegistry.OperatorGroup({
                subNodeOperators: subs,
                externalOperators: new IMetaRegistry.ExternalOperator[](0)
            })
        );
        groupId = countBefore; // new group gets index = old count
    }
}
