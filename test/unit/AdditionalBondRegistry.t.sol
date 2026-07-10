// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { AdditionalBondRegistry } from "src/AdditionalBondRegistry.sol";
import { IAdditionalBondRegistry, BoostStep } from "src/interfaces/IAdditionalBondRegistry.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { MetaRegistryMock } from "../helpers/mocks/MetaRegistryMock.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract AdditionalBondRegistryBaseTest is Test, Utilities, Fixtures {
    CuratedMock public module;
    AdditionalBondRegistry public additionalBondRegistry;
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

        additionalBondRegistry = new AdditionalBondRegistry({
            module: address(module),
            curveMultiplierCooldown: CURVE_MULTIPLIER_COOLDOWN
        });
        // Non-empty placeholder; suites that care about the scale replace it via setBoostSteps.
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: 100, weightMultiplier: 100 });
        _enableInitializers(address(additionalBondRegistry));
        additionalBondRegistry.initialize(admin, boostSteps);

        acct = AccountingMock(address(module.ACCOUNTING()));
    }
}

contract AdditionalBondRegistryConstructorTest is AdditionalBondRegistryBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(additionalBondRegistry.MODULE()), address(module));
        assertEq(address(additionalBondRegistry.ACCOUNTING()), address(module.ACCOUNTING()));
        assertEq(address(additionalBondRegistry.META_REGISTRY()), address(metaRegistryMock));
        assertEq(additionalBondRegistry.MAX_CURVE_MULTIPLIER(), 90_000);
        assertEq(additionalBondRegistry.MAX_WEIGHT_MULTIPLIER(), 90_000);
        assertEq(additionalBondRegistry.CURVE_MULTIPLIER_STEP(), 100);
        assertEq(additionalBondRegistry.CURVE_MULTIPLIER_COOLDOWN(), CURVE_MULTIPLIER_COOLDOWN);
    }
}

contract AdditionalBondRegistryInitializeTest is AdditionalBondRegistryBaseTest {
    function test_initialize_SetsAdmin() public view {
        assertTrue(additionalBondRegistry.hasRole(additionalBondRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module), CURVE_MULTIPLIER_COOLDOWN);
        _enableInitializers(address(tp));
        vm.expectRevert(IAdditionalBondRegistry.ZeroAdminAddress.selector);
        tp.initialize(address(0), new BoostStep[](0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        additionalBondRegistry.initialize(admin, new BoostStep[](0));
    }

    function test_initialize_RevertWhen_EmptyBoostSteps() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module), CURVE_MULTIPLIER_COOLDOWN);
        _enableInitializers(address(tp));
        vm.expectRevert(IAdditionalBondRegistry.EmptyBoostSteps.selector);
        tp.initialize(admin, new BoostStep[](0));
    }

    function test_initialize_SetsBoostSteps() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module), CURVE_MULTIPLIER_COOLDOWN);
        _enableInitializers(address(tp));
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: 5_000, weightMultiplier: 2_000 });
        tp.initialize(admin, boostSteps);

        assertEq(tp.getBoostSteps().length, 1);
        assertEq(tp.getBoostSteps()[0].minCurveMultiplier, 5_000);
        assertEq(tp.getBoostSteps()[0].weightMultiplier, 2_000);
    }
}

contract AdditionalBondRegistrySetBoostStepsTest is AdditionalBondRegistryBaseTest {
    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function _boostSteps() internal pure returns (BoostStep[] memory boostSteps) {
        boostSteps = new BoostStep[](2);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(T1_WEIGHT) });
        boostSteps[1] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T2_WEIGHT) });
    }

    function _setBoostSteps(BoostStep[] memory boostSteps) internal {
        vm.prank(admin);
        additionalBondRegistry.setBoostSteps(boostSteps);
    }

    function test_setBoostSteps() public {
        BoostStep[] memory boostSteps = _boostSteps();
        vm.expectEmit(address(additionalBondRegistry));
        emit IAdditionalBondRegistry.BoostStepsSet(boostSteps);
        _setBoostSteps(boostSteps);

        BoostStep[] memory stored = additionalBondRegistry.getBoostSteps();
        assertEq(stored.length, 2);
        assertEq(stored[0].minCurveMultiplier, T1_BOND);
        assertEq(stored[0].weightMultiplier, T1_WEIGHT);
        assertEq(stored[1].minCurveMultiplier, T2_BOND);
        assertEq(stored[1].weightMultiplier, T2_WEIGHT);
    }

    function test_setBoostSteps_Replaces() public {
        _setBoostSteps(_boostSteps());
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T2_WEIGHT) });
        _setBoostSteps(boostSteps);
        assertEq(additionalBondRegistry.getBoostSteps().length, 1);
    }

    function test_setBoostSteps_AllowsZeroIncrement() public {
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: 0, weightMultiplier: 0 });
        _setBoostSteps(boostSteps);
        assertEq(additionalBondRegistry.getBoostSteps()[0].minCurveMultiplier, 0);
    }

    function test_setBoostSteps_AllowsMaxIncrement() public {
        uint256 maxCurve = additionalBondRegistry.MAX_CURVE_MULTIPLIER();
        uint256 maxWeight = additionalBondRegistry.MAX_WEIGHT_MULTIPLIER();
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(maxCurve), weightMultiplier: uint128(maxWeight) });
        _setBoostSteps(boostSteps);
        assertEq(additionalBondRegistry.getBoostSteps()[0].minCurveMultiplier, maxCurve);
    }

    function test_setBoostSteps_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(stranger);
        additionalBondRegistry.setBoostSteps(_boostSteps());
    }

    function test_setBoostSteps_RevertWhen_CurveMulAboveMax() public {
        uint256 aboveMax = additionalBondRegistry.MAX_CURVE_MULTIPLIER() + 1;
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(aboveMax), weightMultiplier: uint128(T1_WEIGHT) });
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplier.selector);
        _setBoostSteps(boostSteps);
    }

    function test_setBoostSteps_RevertWhen_WeightMulAboveMax() public {
        uint256 aboveMax = additionalBondRegistry.MAX_WEIGHT_MULTIPLIER() + 1;
        BoostStep[] memory boostSteps = new BoostStep[](1);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(aboveMax) });
        vm.expectRevert(IAdditionalBondRegistry.InvalidWeightMultiplier.selector);
        _setBoostSteps(boostSteps);
    }

    function test_setBoostSteps_RevertWhen_CurveNotAscending() public {
        BoostStep[] memory boostSteps = new BoostStep[](2);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T1_WEIGHT) });
        boostSteps[1] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(T2_WEIGHT) });
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplier.selector);
        _setBoostSteps(boostSteps);
    }

    function test_setBoostSteps_RevertWhen_WeightNotAscending() public {
        BoostStep[] memory boostSteps = new BoostStep[](2);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(T2_WEIGHT) });
        boostSteps[1] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T1_WEIGHT) });
        vm.expectRevert(IAdditionalBondRegistry.InvalidWeightMultiplier.selector);
        _setBoostSteps(boostSteps);
    }
}

contract AdditionalBondRegistryRequestCurveMultiplierBaseTest is AdditionalBondRegistryBaseTest {
    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function _setBoostSteps() internal {
        BoostStep[] memory boostSteps = new BoostStep[](2);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(T1_WEIGHT) });
        boostSteps[1] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T2_WEIGHT) });
        vm.prank(admin);
        additionalBondRegistry.setBoostSteps(boostSteps);
    }
}

contract AdditionalBondRegistryRequestCurveMultiplierTest is AdditionalBondRegistryRequestCurveMultiplierBaseTest {
    function setUp() public override {
        super.setUp();
        _setBoostSteps();
    }

    function test_requestCurveMultiplier_Upgrade_Tier0ToTier1() public {
        vm.expectEmit(true, false, false, true, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierRequested(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 1);
        assertEq(metaRegistryMock.lastChangedBoostOperatorId(), 0);
    }

    function test_requestCurveMultiplier_Upgrade_Tier1ToTier2() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        vm.expectEmit(true, false, false, true, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierRequested(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T2_WEIGHT);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }

    function test_requestCurveMultiplier_Downgrade_Tier1ToTier0() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        uint256 expectedCooldown = block.timestamp + CURVE_MULTIPLIER_COOLDOWN;
        vm.expectEmit(true, false, false, true, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierCooldownSet(0, expectedCooldown);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);

        // The bond multiplier stays until apply, so it remains above MAX_BP while the weight already dropped.
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 2);
    }

    function test_requestCurveMultiplier_Upgrade_ClearsCooldownIfActive() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP); // cooldown active, weight dropped

        vm.prank(nodeOperatorOwner);
        vm.expectEmit(true, false, false, false, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierCooldownRemoved(0);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }

    function test_requestCurveMultiplier_WithinStep() public {
        // Raising within the same step changes the bond multiplier but not the weight (decoupled).
        uint256 within = T1_BOND + additionalBondRegistry.CURVE_MULTIPLIER_STEP(); // 1%-aligned, still first step
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, within);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + within);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
    }

    function test_requestCurveMultiplier_RevertWhen_NotOwner() public {
        vm.expectRevert(IAdditionalBondRegistry.SenderIsNotOperatorOwner.selector);
        vm.prank(stranger);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
    }

    function test_requestCurveMultiplier_RevertWhen_CurveMultiplierAboveMax() public {
        uint256 aboveMax = additionalBondRegistry.MAX_CURVE_MULTIPLIER() + 1;
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplier.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, aboveMax);
    }

    function test_requestCurveMultiplier_RevertWhen_NotStepAligned() public {
        // Not a multiple of CURVE_MULTIPLIER_STEP (1%).
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplier.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND + 1);
    }

    function test_requestCurveMultiplier_RevertWhen_SameCurveMultiplier() public {
        vm.expectRevert(IAdditionalBondRegistry.SameCurveMultiplier.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
    }

    function test_requestCurveMultiplier_Upgrade_SucceedsWhenBondCoversScaledRequirement() public {
        uint256 baseRequired = 10 ether;
        acct.mock_setRequiredBond(0, baseRequired);
        uint256 scaledRequired = (baseRequired * (MAX_BP + T1_BOND)) / MAX_BP;
        vm.deal(address(this), scaledRequired);
        acct.depositETH{ value: scaledRequired }(0);

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
    }

    function test_requestCurveMultiplier_RevertWhen_BondCoversBaseButNotScaledRequirement() public {
        uint256 baseRequired = 10 ether;
        acct.mock_setRequiredBond(0, baseRequired);
        uint256 scaledRequired = (baseRequired * (MAX_BP + T1_BOND)) / MAX_BP;
        // 1 wei short of the scaled requirement (would suffice at MAX_BP).
        vm.deal(address(this), scaledRequired - 1);
        acct.depositETH{ value: scaledRequired - 1 }(0);

        vm.expectRevert(IAdditionalBondRegistry.InsufficientBond.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
    }

    function test_requestCurveMultiplier_RevertWhen_CurveMultiplierCooldownActive() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        vm.expectRevert(IAdditionalBondRegistry.CurveMultiplierCooldownActive.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
    }

    function test_requestCurveMultiplier_RevertWhen_DowngradeReducesViaIntermediateStep() public {
        // A middle step at 7_000: during a downgrade cooldown it reads as a higher weight than the pending
        // step, but it is still below the committed multiplier, so the cooldown must block it — otherwise
        // the operator sheds bond before the cooldown elapses.
        BoostStep[] memory boostSteps = new BoostStep[](3);
        boostSteps[0] = BoostStep({ minCurveMultiplier: uint128(T1_BOND), weightMultiplier: uint128(T1_WEIGHT) });
        boostSteps[1] = BoostStep({ minCurveMultiplier: 7_000, weightMultiplier: 4_000 });
        boostSteps[2] = BoostStep({ minCurveMultiplier: uint128(T2_BOND), weightMultiplier: uint128(T2_WEIGHT) });
        vm.prank(admin);
        additionalBondRegistry.setBoostSteps(boostSteps);

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        vm.expectRevert(IAdditionalBondRegistry.CurveMultiplierCooldownActive.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 7_000);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }
}

contract AdditionalBondRegistryApplyCurveMultiplierTest is AdditionalBondRegistryRequestCurveMultiplierBaseTest {
    function setUp() public override {
        super.setUp();
        _setBoostSteps();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
    }

    function test_applyCurveMultiplier() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);

        vm.expectEmit(true, false, false, false, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierCooldownRemoved(0);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplier(0);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP);
    }

    function test_applyCurveMultiplier_SettlesToRequestedNotDefault() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);

        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplier(0);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
    }

    function test_applyCurveMultiplier_RevertWhen_NotOwner() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.expectRevert(IAdditionalBondRegistry.SenderIsNotOperatorOwner.selector);
        vm.prank(stranger);
        additionalBondRegistry.applyCurveMultiplier(0);
    }

    function test_applyCurveMultiplier_RevertWhen_NoCurveMultiplierCooldown() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplier(0);
        vm.expectRevert(IAdditionalBondRegistry.NoCurveMultiplierCooldown.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplier(0);
    }

    function test_applyCurveMultiplier_RevertWhen_CurveMultiplierCooldownNotElapsed() public {
        vm.expectRevert(IAdditionalBondRegistry.CurveMultiplierCooldownNotElapsed.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplier(0);
    }
}

contract AdditionalBondRegistryViewsTest is AdditionalBondRegistryRequestCurveMultiplierBaseTest {
    function setUp() public override {
        super.setUp();
        _setBoostSteps();
    }

    function test_getBoostSteps() public view {
        BoostStep[] memory boostSteps = additionalBondRegistry.getBoostSteps();
        assertEq(boostSteps.length, 2);
        assertEq(boostSteps[0].minCurveMultiplier, T1_BOND);
        assertEq(boostSteps[0].weightMultiplier, T1_WEIGHT);
    }

    function test_getWeightBoostMultiplierBP_Default() public view {
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_AfterUpgrade() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
    }

    function test_getWeightBoostMultiplierBP_DuringDowngradeCooldown() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        // Weight follows the pending (lower) step while Accounting still holds the higher multiplier.
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }
}
