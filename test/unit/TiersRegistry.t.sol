// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { TiersRegistry } from "src/TiersRegistry.sol";
import { ITiersRegistry, TierInfo, OperatorTierState } from "src/interfaces/ITiersRegistry.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { MetaRegistryMock } from "../helpers/mocks/MetaRegistryMock.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract TiersRegistryBaseTest is Test, Utilities, Fixtures {
    CuratedMock public module;
    TiersRegistry public tiersRegistry;
    MetaRegistryMock public metaRegistryMock;
    AccountingMock internal acct;

    address public admin;
    address public nodeOperatorOwner;
    address public stranger;

    uint16 internal constant MAX_BP = 10_000;
    uint256 internal constant CURVE_MULTIPLIER_COOLDOWN = 7 days;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        stranger = nextAddress("STRANGER");

        module = new CuratedMock();
        module.mock_setNodeOperatorsCount(3);
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperatorOwner,
                rewardAddress: nodeOperatorOwner,
                extendedManagerPermissions: true
            })
        );

        metaRegistryMock = new MetaRegistryMock();
        module.mock_setMetaRegistry(address(metaRegistryMock));

        tiersRegistry = new TiersRegistry({
            module: address(module),
            curveMultiplierCooldown: CURVE_MULTIPLIER_COOLDOWN
        });
        _enableInitializers(address(tiersRegistry));
        tiersRegistry.initialize(admin);

        acct = AccountingMock(address(module.ACCOUNTING()));
    }
}

contract TiersRegistryConstructorTest is TiersRegistryBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(tiersRegistry.MODULE()), address(module));
        assertEq(address(tiersRegistry.ACCOUNTING()), address(module.ACCOUNTING()));
        assertEq(address(tiersRegistry.META_REGISTRY()), address(metaRegistryMock));
        assertEq(tiersRegistry.MAX_CURVE_MULTIPLIER_INC(), 100_000);
        assertEq(tiersRegistry.MAX_WEIGHT_MULTIPLIER_INC(), 100_000);
        assertEq(tiersRegistry.CURVE_MULTIPLIER_COOLDOWN(), CURVE_MULTIPLIER_COOLDOWN);
    }
}

contract TiersRegistryInitializeTest is TiersRegistryBaseTest {
    function test_initialize_SetsAdmin() public view {
        assertTrue(tiersRegistry.hasRole(tiersRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        TiersRegistry tp = new TiersRegistry(address(module), CURVE_MULTIPLIER_COOLDOWN);
        _enableInitializers(address(tp));
        vm.expectRevert(ITiersRegistry.ZeroAdminAddress.selector);
        tp.initialize(address(0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tiersRegistry.initialize(admin);
    }
}

contract TiersRegistryAddTierTest is TiersRegistryBaseTest {
    function _addTier(uint256 bond, uint256 weight) internal returns (uint256 tierId) {
        vm.prank(admin);
        tierId = tiersRegistry.addTier(bond, weight);
    }

    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function test_addTier() public {
        vm.expectEmit(true, false, false, true, address(tiersRegistry));
        emit ITiersRegistry.TierAdded(1, T1_BOND, T1_WEIGHT);
        uint256 tierId = _addTier(T1_BOND, T1_WEIGHT);

        assertEq(tierId, 1);
        assertEq(tiersRegistry.getTiersCount(), 1);
        TierInfo memory t = tiersRegistry.getTierInfo(1);
        assertEq(t.curveMultiplierInc, T1_BOND);
        assertEq(t.weightMultiplierInc, T1_WEIGHT);
    }

    function test_addTier_SecondTier() public {
        _addTier(T1_BOND, T1_WEIGHT);
        uint256 tierId = _addTier(T2_BOND, T2_WEIGHT);
        assertEq(tierId, 2);
        assertEq(tiersRegistry.getTiersCount(), 2);
    }

    function test_addTier_AllowsZeroCurveMultiplierInc() public {
        uint256 tierId = _addTier(0, T1_WEIGHT);
        TierInfo memory t = tiersRegistry.getTierInfo(tierId);
        assertEq(t.curveMultiplierInc, 0);
        assertEq(t.weightMultiplierInc, T1_WEIGHT);
    }

    function test_addTier_AllowsZeroWeightMultiplierInc() public {
        uint256 tierId = _addTier(T1_BOND, 0);
        TierInfo memory t = tiersRegistry.getTierInfo(tierId);
        assertEq(t.curveMultiplierInc, T1_BOND);
        assertEq(t.weightMultiplierInc, 0);
    }

    function test_addTier_AllowsMaxIncrement() public {
        uint256 maxCurve = tiersRegistry.MAX_CURVE_MULTIPLIER_INC();
        uint256 maxWeight = tiersRegistry.MAX_WEIGHT_MULTIPLIER_INC();
        uint256 tierId = _addTier(maxCurve, maxWeight);
        TierInfo memory t = tiersRegistry.getTierInfo(tierId);
        assertEq(t.curveMultiplierInc, maxCurve);
        assertEq(t.weightMultiplierInc, maxWeight);
    }

    function test_addTier_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(stranger);
        tiersRegistry.addTier(T1_BOND, T1_WEIGHT);
    }

    function test_addTier_RevertWhen_BondMulAboveMax() public {
        uint256 aboveMax = tiersRegistry.MAX_CURVE_MULTIPLIER_INC() + 1;
        vm.expectRevert(ITiersRegistry.InvalidCurveMultiplier.selector);
        _addTier(aboveMax, T1_WEIGHT);
    }

    function test_addTier_RevertWhen_WeightMulAboveMax() public {
        uint256 aboveMax = tiersRegistry.MAX_WEIGHT_MULTIPLIER_INC() + 1;
        vm.expectRevert(ITiersRegistry.InvalidWeightMultiplier.selector);
        _addTier(T1_BOND, aboveMax);
    }
}

contract TiersRegistrySelectTierBaseTest is TiersRegistryBaseTest {
    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function _addTier(uint256 bond, uint256 weight) internal returns (uint256 tierId) {
        vm.prank(admin);
        tierId = tiersRegistry.addTier(bond, weight);
    }
}

contract TiersRegistrySelectTierTest is TiersRegistrySelectTierBaseTest {
    function setUp() public override {
        super.setUp();
        _addTier(T1_BOND, T1_WEIGHT);
        _addTier(T2_BOND, T2_WEIGHT);
    }

    function test_selectTier_Upgrade_Tier0ToTier1() public {
        vm.expectEmit(true, false, false, true, address(tiersRegistry));
        emit ITiersRegistry.TierSelected(0, 1);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        assertEq(tiersRegistry.getOperatorTierState(0).tierId, 1);
        assertEq(tiersRegistry.getOperatorTierState(0).weightMultiplier, MAX_BP + T1_WEIGHT);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(metaRegistryMock.refreshOperatorWeightCallCount(), 1);
        assertEq(metaRegistryMock.lastRefreshedOperatorId(), 0);
    }

    function test_selectTier_Upgrade_Tier1ToTier2() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        vm.expectEmit(true, false, false, true, address(tiersRegistry));
        emit ITiersRegistry.TierSelected(0, 2);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 2);

        OperatorTierState memory s = tiersRegistry.getOperatorTierState(0);
        assertEq(s.tierId, 2);
        assertEq(s.weightMultiplier, MAX_BP + T2_WEIGHT);
        assertEq(s.curveMultiplier, MAX_BP + T2_BOND);
        assertEq(s.curveMultiplierCooldownUntil, 0);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }

    function test_selectTier_Downgrade_Tier1ToTier0() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        uint256 expectedCooldown = block.timestamp + CURVE_MULTIPLIER_COOLDOWN;
        vm.expectEmit(true, false, false, true, address(tiersRegistry));
        emit ITiersRegistry.CurveMultiplierCooldownSet(0, expectedCooldown);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 0);

        OperatorTierState memory s = tiersRegistry.getOperatorTierState(0);
        assertEq(s.tierId, 0);
        assertEq(s.weightMultiplier, MAX_BP);
        assertEq(s.curveMultiplierCooldownUntil, expectedCooldown);
        // Tier 0 keeps the pre-downgrade multiplier until release, so it stays above MAX_BP.
        assertEq(s.curveMultiplier, MAX_BP + T1_BOND);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(metaRegistryMock.refreshOperatorWeightCallCount(), 2);
    }

    function test_selectTier_Upgrade_ClearsCooldownIfActive() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 0);
        assertGt(tiersRegistry.getOperatorTierState(0).curveMultiplierCooldownUntil, 0);

        vm.prank(nodeOperatorOwner);
        vm.expectEmit(true, false, false, false, address(tiersRegistry));
        emit ITiersRegistry.CurveMultiplierCooldownRemoved(0);
        tiersRegistry.selectTier(0, 2);

        assertEq(tiersRegistry.getOperatorTierState(0).curveMultiplierCooldownUntil, 0);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }

    function test_selectTier_RevertWhen_NotOwner() public {
        vm.expectRevert(ITiersRegistry.SenderIsNotOperatorOwner.selector);
        vm.prank(stranger);
        tiersRegistry.selectTier(0, 1);
    }

    function test_selectTier_RevertWhen_InvalidTierId() public {
        vm.expectRevert(ITiersRegistry.InvalidTierId.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 99);
    }

    function test_selectTier_RevertWhen_SameTier() public {
        vm.expectRevert(ITiersRegistry.SameTier.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 0);
    }

    function test_selectTier_Upgrade_SucceedsWhenBondCoversScaledRequirement() public {
        uint256 baseRequired = 10 ether;
        acct.mock_setRequiredBond(0, baseRequired);
        uint256 scaledRequired = (baseRequired * (MAX_BP + T1_BOND)) / MAX_BP;
        vm.deal(address(this), scaledRequired);
        acct.depositETH{ value: scaledRequired }(0);

        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        assertEq(tiersRegistry.getOperatorTierState(0).tierId, 1);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
    }

    function test_selectTier_RevertWhen_BondCoversBaseButNotScaledRequirement() public {
        uint256 baseRequired = 10 ether;
        acct.mock_setRequiredBond(0, baseRequired);
        uint256 scaledRequired = (baseRequired * (MAX_BP + T1_BOND)) / MAX_BP;
        // 1 wei short of the scaled requirement (would suffice at MAX_BP).
        vm.deal(address(this), scaledRequired - 1);
        acct.depositETH{ value: scaledRequired - 1 }(0);

        vm.expectRevert(ITiersRegistry.InsufficientBondForTier.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);
    }

    function test_selectTier_RevertWhen_CurveMultiplierCooldownActive() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 2);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        vm.expectRevert(ITiersRegistry.CurveMultiplierCooldownActive.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 0);
    }

    function test_selectTier_RevertWhen_DowngradeReducesViaIntermediateTier() public {
        uint256 t3Bond = 7_000; // between tier 1 (5_000) and the held tier 2 (10_000)
        _addTier(t3Bond, T1_WEIGHT);

        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 2);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        // Tier 3 reads as an upgrade vs tier 1's nominal value but is still below the held tier-2 value,
        // so the cooldown must block it — otherwise the operator sheds bond before the cooldown elapses.
        vm.expectRevert(ITiersRegistry.CurveMultiplierCooldownActive.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 3);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }
}

contract TiersRegistryReleaseCurveMultiplierTest is TiersRegistrySelectTierBaseTest {
    function setUp() public override {
        super.setUp();
        _addTier(T1_BOND, T1_WEIGHT);
        _addTier(T2_BOND, T2_WEIGHT);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 0);
    }

    function test_releaseCurveMultiplier() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);

        vm.expectEmit(true, false, false, false, address(tiersRegistry));
        emit ITiersRegistry.CurveMultiplierCooldownRemoved(0);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.releaseCurveMultiplier(0);

        assertEq(tiersRegistry.getOperatorTierState(0).curveMultiplierCooldownUntil, 0);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP);
    }

    function test_releaseCurveMultiplier_SettlesToCurrentTierNotDefault() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 2);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);

        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.releaseCurveMultiplier(0);

        assertEq(tiersRegistry.getOperatorTierState(0).curveMultiplierCooldownUntil, 0);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
    }

    function test_releaseCurveMultiplier_RevertWhen_NotOwner() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.expectRevert(ITiersRegistry.SenderIsNotOperatorOwner.selector);
        vm.prank(stranger);
        tiersRegistry.releaseCurveMultiplier(0);
    }

    function test_releaseCurveMultiplier_RevertWhen_NoCurveMultiplierCooldown() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.releaseCurveMultiplier(0);
        vm.expectRevert(ITiersRegistry.NoCurveMultiplierCooldown.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.releaseCurveMultiplier(0);
    }

    function test_releaseCurveMultiplier_RevertWhen_CurveMultiplierCooldownNotElapsed() public {
        vm.expectRevert(ITiersRegistry.CurveMultiplierCooldownNotElapsed.selector);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.releaseCurveMultiplier(0);
    }
}

contract TiersRegistryViewsTest is TiersRegistrySelectTierBaseTest {
    function setUp() public override {
        super.setUp();
        _addTier(T1_BOND, T1_WEIGHT);
        _addTier(T2_BOND, T2_WEIGHT);
    }

    function test_getTiersCount() public view {
        assertEq(tiersRegistry.getTiersCount(), 2);
    }

    function test_getTierInfo_Tier0() public view {
        TierInfo memory t = tiersRegistry.getTierInfo(0);
        assertEq(t.curveMultiplierInc, 0);
        assertEq(t.weightMultiplierInc, 0);
    }

    function test_getTierInfo_Tier1() public view {
        TierInfo memory t = tiersRegistry.getTierInfo(1);
        assertEq(t.curveMultiplierInc, T1_BOND);
        assertEq(t.weightMultiplierInc, T1_WEIGHT);
    }

    function test_getTierInfo_RevertWhen_InvalidTierId() public {
        vm.expectRevert(ITiersRegistry.InvalidTierId.selector);
        tiersRegistry.getTierInfo(99);
    }

    function test_getOperatorTierState_Default() public view {
        OperatorTierState memory s = tiersRegistry.getOperatorTierState(0);
        assertEq(s.tierId, 0);
        assertEq(s.weightMultiplier, MAX_BP);
        assertEq(s.curveMultiplier, MAX_BP);
        assertEq(s.curveMultiplierCooldownUntil, 0);
    }

    function test_getOperatorTierState_AfterUpgrade() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);
        OperatorTierState memory s = tiersRegistry.getOperatorTierState(0);
        assertEq(s.tierId, 1);
        assertEq(s.weightMultiplier, MAX_BP + T1_WEIGHT);
        assertEq(s.curveMultiplier, MAX_BP + T1_BOND);
        assertEq(s.curveMultiplierCooldownUntil, 0);
    }

    function test_getOperatorTierState_AfterDowngrade_CooldownMultiplierDivergesFromTier() public {
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 2);
        vm.prank(nodeOperatorOwner);
        tiersRegistry.selectTier(0, 1);

        OperatorTierState memory s = tiersRegistry.getOperatorTierState(0);
        assertEq(s.tierId, 1);
        assertEq(s.weightMultiplier, MAX_BP + T1_WEIGHT);
        assertEq(s.curveMultiplier, MAX_BP + T2_BOND);
        assertEq(s.curveMultiplierCooldownUntil, block.timestamp + CURVE_MULTIPLIER_COOLDOWN);
    }
}
