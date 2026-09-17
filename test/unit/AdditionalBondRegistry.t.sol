// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { AdditionalBondRegistry } from "src/AdditionalBondRegistry.sol";
import { IAdditionalBondRegistry } from "src/interfaces/IAdditionalBondRegistry.sol";
import { IBaseWeightBoostProvider } from "src/interfaces/IBaseWeightBoostProvider.sol";
import { IStepwiseWeightBoost, Step } from "src/interfaces/IStepwiseWeightBoost.sol";

import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { CuratedProviderFixture } from "../helpers/CuratedProviderFixture.sol";
import { StepwiseWeightBoostBehaviour } from "../helpers/StepwiseWeightBoostBehaviour.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract AdditionalBondRegistryBaseTest is Test, Utilities, Fixtures, CuratedProviderFixture {
    AdditionalBondRegistry public additionalBondRegistry;
    AccountingMock internal acct;

    address public admin;
    address public nodeOperatorOwner;
    address public stranger;

    uint16 internal constant MAX_BP = 10_000;
    uint256 internal constant CURVE_MULTIPLIER_REDUCTION_COOLDOWN = 7 days;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        stranger = nextAddress("STRANGER");

        _deployModuleWithMetaRegistryMock(3);
        _setNodeOperatorOwner(nodeOperatorOwner);

        additionalBondRegistry = new AdditionalBondRegistry({ module: address(module) });
        // Non-empty placeholder; suites that care about the scale replace it via setSteps.
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 100, value: 100 });
        _enableInitializers(address(additionalBondRegistry));
        additionalBondRegistry.initialize(admin, CURVE_MULTIPLIER_REDUCTION_COOLDOWN, steps);

        acct = AccountingMock(address(module.ACCOUNTING()));
    }
}

contract AdditionalBondRegistryConstructorTest is AdditionalBondRegistryBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(additionalBondRegistry.MODULE()), address(module));
        assertEq(address(additionalBondRegistry.ACCOUNTING()), address(module.ACCOUNTING()));
        assertEq(address(additionalBondRegistry.META_REGISTRY()), address(metaRegistryMock));
        assertEq(additionalBondRegistry.MAX_CURVE_MULTIPLIER(), 9 * uint256(MAX_BP));
        assertEq(additionalBondRegistry.MAX_STEP_VALUE(), 9 * uint256(MAX_BP));
        assertEq(additionalBondRegistry.CURVE_MULTIPLIER_STEP(), 100);
        assertEq(additionalBondRegistry.MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN(), 365 days);
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IBaseWeightBoostProvider.ZeroModuleAddress.selector);
        new AdditionalBondRegistry(address(0));
    }
}

contract AdditionalBondRegistryInitializeTest is AdditionalBondRegistryBaseTest {
    function test_initialize_SetsAdmin() public view {
        assertTrue(additionalBondRegistry.hasRole(additionalBondRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_SetsCooldown() public view {
        assertEq(additionalBondRegistry.getCurveMultiplierReductionCooldown(), CURVE_MULTIPLIER_REDUCTION_COOLDOWN);
    }

    function test_initialize_RevertWhen_ZeroCooldown() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplierReductionCooldown.selector);
        tp.initialize(admin, 0, new Step[](0));
    }

    function test_initialize_RevertWhen_CooldownExceedsMax() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplierReductionCooldown.selector);
        tp.initialize(admin, 365 days + 1, new Step[](0));
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(IBaseWeightBoostProvider.ZeroAdminAddress.selector);
        tp.initialize(address(0), CURVE_MULTIPLIER_REDUCTION_COOLDOWN, new Step[](0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        additionalBondRegistry.initialize(admin, CURVE_MULTIPLIER_REDUCTION_COOLDOWN, new Step[](0));
    }

    function test_initialize_RevertWhen_EmptySteps() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(IStepwiseWeightBoost.InvalidStepCount.selector);
        tp.initialize(admin, CURVE_MULTIPLIER_REDUCTION_COOLDOWN, new Step[](0));
    }

    function test_initialize_SetsSteps() public {
        AdditionalBondRegistry tp = new AdditionalBondRegistry(address(module));
        _enableInitializers(address(tp));
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 5_000, value: 2_000 });
        tp.initialize(admin, CURVE_MULTIPLIER_REDUCTION_COOLDOWN, steps);

        assertEq(tp.getSteps().length, 1);
        assertEq(tp.getSteps()[0].threshold, 5_000);
        assertEq(tp.getSteps()[0].value, 2_000);
    }
}

contract AdditionalBondRegistrySetStepsTest is AdditionalBondRegistryBaseTest, StepwiseWeightBoostBehaviour {
    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function _stepwise() internal view override returns (IStepwiseWeightBoost) {
        return IStepwiseWeightBoost(address(additionalBondRegistry));
    }

    function _stepwiseAdmin() internal view override returns (address) {
        return admin;
    }

    function _stepwiseSteps(uint256 count) internal view override returns (Step[] memory steps) {
        steps = new Step[](count);
        for (uint256 i; i < count; ++i) {
            // Curve multiplier increments are 1%-aligned and may start at zero.
            steps[i] = Step({ threshold: uint128(i * 100), value: uint128((i + 1) * 100) });
        }
    }

    function _steps() internal pure returns (Step[] memory steps) {
        steps = new Step[](2);
        steps[0] = Step({ threshold: uint128(T1_BOND), value: uint128(T1_WEIGHT) });
        steps[1] = Step({ threshold: uint128(T2_BOND), value: uint128(T2_WEIGHT) });
    }

    function _setSteps(Step[] memory steps) internal {
        vm.prank(admin);
        additionalBondRegistry.setSteps(steps);
    }

    function test_setSteps() public {
        Step[] memory steps = _steps();
        vm.expectEmit(address(additionalBondRegistry));
        emit IStepwiseWeightBoost.StepsSet(steps);
        _setSteps(steps);

        Step[] memory stored = additionalBondRegistry.getSteps();
        assertEq(stored.length, 2);
        assertEq(stored[0].threshold, T1_BOND);
        assertEq(stored[0].value, T1_WEIGHT);
        assertEq(stored[1].threshold, T2_BOND);
        assertEq(stored[1].value, T2_WEIGHT);
    }

    function test_setSteps_NotifiesProviderConfigChanged() public {
        _setSteps(_steps());
        assertEq(metaRegistryMock.notifyWeightBoostProviderConfigChangedCallCount(), 1);
    }

    function test_setSteps_AllowsZeroStep() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 0, value: 0 });
        _setSteps(steps);
        assertEq(additionalBondRegistry.getSteps()[0].threshold, 0);
    }

    function test_setSteps_AllowsMaxThresholdAndValue() public {
        uint256 maxCurve = additionalBondRegistry.MAX_CURVE_MULTIPLIER();
        uint256 maxWeight = additionalBondRegistry.MAX_STEP_VALUE();
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(maxCurve), value: uint128(maxWeight) });
        _setSteps(steps);
        assertEq(additionalBondRegistry.getSteps()[0].threshold, maxCurve);
    }

    function test_setSteps_RevertWhen_ThresholdAboveMax() public {
        uint256 aboveMax = additionalBondRegistry.MAX_CURVE_MULTIPLIER() + 1;
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(aboveMax), value: uint128(T1_WEIGHT) });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }

    function test_setSteps_RevertWhen_ThresholdNotAligned() public {
        uint256 offGrid = T1_BOND + additionalBondRegistry.CURVE_MULTIPLIER_STEP() / 2;
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(offGrid), value: uint128(T1_WEIGHT) });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }
}

contract AdditionalBondRegistryRequestCurveMultiplierBaseTest is AdditionalBondRegistryBaseTest {
    uint256 constant T1_BOND = 5_000;
    uint256 constant T1_WEIGHT = 2_000;
    uint256 constant T2_BOND = 10_000;
    uint256 constant T2_WEIGHT = 8_000;

    function _setSteps() internal {
        Step[] memory steps = new Step[](2);
        steps[0] = Step({ threshold: uint128(T1_BOND), value: uint128(T1_WEIGHT) });
        steps[1] = Step({ threshold: uint128(T2_BOND), value: uint128(T2_WEIGHT) });
        vm.prank(admin);
        additionalBondRegistry.setSteps(steps);
    }
}

contract AdditionalBondRegistryRequestCurveMultiplierTest is AdditionalBondRegistryRequestCurveMultiplierBaseTest {
    function setUp() public override {
        super.setUp();
        _setSteps();
    }

    function test_requestCurveMultiplier_Upgrade_Tier0ToTier1() public {
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

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T2_WEIGHT);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
    }

    function test_requestCurveMultiplier_Downgrade_Tier1ToTier0() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        uint256 expectedCooldown = block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN;
        vm.expectEmit(true, false, false, true, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierReductionRequested(0, 0, expectedCooldown);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);

        // The bond multiplier stays until apply, so it remains above MAX_BP while the weight already dropped.
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).curveMultiplier, 0);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).cooldownUntil, expectedCooldown);
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
        emit IAdditionalBondRegistry.CurveMultiplierReductionCancelled(0);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).cooldownUntil, 0);
    }

    function test_requestCurveMultiplier_WithinStep() public {
        // Raising within the same step changes the bond multiplier but not the weight (decoupled).
        uint256 within = T1_BOND + additionalBondRegistry.CURVE_MULTIPLIER_STEP(); // 1%-aligned, still first step
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, within);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + within);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestCurveMultiplier_RevertWhen_NotOwner() public {
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
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

    function test_requestCurveMultiplier_LowerAgainResetsCooldown() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND); // downgrade -> cooldown, pending = T1_BOND

        // Lowering further during the cooldown is allowed: it just resets the pending target and the cooldown.
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP); // weight follows new pending (0)
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND); // bond untouched until applyCurveMultiplierReduction
    }

    function test_requestCurveMultiplier_LowerAgainWithinStepDoesNotNotify() public {
        uint256 withinFirstStep = T1_BOND + additionalBondRegistry.CURVE_MULTIPLIER_STEP();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, withinFirstStep);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestCurveMultiplier_LowerToIntermediateResetsCooldown() public {
        // A middle step at 7_000: an intermediate value is below the committed multiplier, so it is a lower —
        // it resets the pending target and weight but never touches the bond in Accounting.
        Step[] memory steps = new Step[](3);
        steps[0] = Step({ threshold: uint128(T1_BOND), value: uint128(T1_WEIGHT) });
        steps[1] = Step({ threshold: 7_000, value: 4_000 });
        steps[2] = Step({ threshold: uint128(T2_BOND), value: uint128(T2_WEIGHT) });
        vm.prank(admin);
        additionalBondRegistry.setSteps(steps);

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND); // downgrade -> cooldown, pending = T1_BOND

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 7_000); // still below committed -> lower, resets

        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + 4_000); // weight -> middle step
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND); // bond untouched
    }
}

contract AdditionalBondRegistryApplyCurveMultiplierReductionTest is
    AdditionalBondRegistryRequestCurveMultiplierBaseTest
{
    function setUp() public override {
        super.setUp();
        _setSteps();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
    }

    function test_applyCurveMultiplierReduction() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN + 1);

        vm.expectEmit(true, false, false, true, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierReductionApplied(0, 0);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplierReduction(0);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).curveMultiplier, 0);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).cooldownUntil, 0);
    }

    function test_applyCurveMultiplierReduction_SettlesToRequestedNotDefault() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T2_BOND);

        vm.warp(block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplierReduction(0);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
    }

    function test_applyCurveMultiplierReduction_RevertWhen_NotOwner() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN + 1);
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        additionalBondRegistry.applyCurveMultiplierReduction(0);
    }

    function test_applyCurveMultiplierReduction_RevertWhen_NoCurveMultiplierReductionCooldown() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN + 1);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplierReduction(0);
        vm.expectRevert(IAdditionalBondRegistry.NoCurveMultiplierReductionCooldown.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplierReduction(0);
    }

    function test_applyCurveMultiplierReduction_RevertWhen_CurveMultiplierReductionCooldownNotElapsed() public {
        vm.expectRevert(IAdditionalBondRegistry.CurveMultiplierReductionCooldownNotElapsed.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.applyCurveMultiplierReduction(0);
    }
}

contract AdditionalBondRegistryCancelCurveMultiplierReductionTest is
    AdditionalBondRegistryRequestCurveMultiplierBaseTest
{
    function setUp() public override {
        super.setUp();
        _setSteps();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, 0);
    }

    function test_cancelCurveMultiplierReduction() public {
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.expectEmit(true, false, false, false, address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierReductionCancelled(0);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);

        // The weight returns to the multiplier Accounting still holds; the bond was never touched.
        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).cooldownUntil, 0);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_cancelCurveMultiplierReduction_AfterCooldown() public {
        vm.warp(block.timestamp + CURVE_MULTIPLIER_REDUCTION_COOLDOWN + 1);

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);

        assertEq(acct.getBondCurveMultiplier(0), MAX_BP + T1_BOND);
        assertEq(additionalBondRegistry.getPendingCurveMultiplierReduction(0).cooldownUntil, 0);
    }

    function test_cancelCurveMultiplierReduction_DoesNotNotifyWhenWithinStep() public {
        uint256 withinFirstStep = T1_BOND + additionalBondRegistry.CURVE_MULTIPLIER_STEP();
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, withinFirstStep);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND); // pending, same band as current
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);

        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_cancelCurveMultiplierReduction_RevertWhen_NotOwner() public {
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);
    }

    function test_cancelCurveMultiplierReduction_RevertWhen_NoPendingReduction() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);

        vm.expectRevert(IAdditionalBondRegistry.NoCurveMultiplierReductionCooldown.selector);
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.cancelCurveMultiplierReduction(0);
    }
}

contract AdditionalBondRegistrySetCurveMultiplierReductionCooldownTest is AdditionalBondRegistryBaseTest {
    function test_setCurveMultiplierReductionCooldown() public {
        vm.expectEmit(address(additionalBondRegistry));
        emit IAdditionalBondRegistry.CurveMultiplierReductionCooldownSet(30 days);
        vm.prank(admin);
        additionalBondRegistry.setCurveMultiplierReductionCooldown(30 days);

        assertEq(additionalBondRegistry.getCurveMultiplierReductionCooldown(), 30 days);
    }

    function test_setCurveMultiplierReductionCooldown_Max() public {
        vm.prank(admin);
        additionalBondRegistry.setCurveMultiplierReductionCooldown(365 days);

        assertEq(additionalBondRegistry.getCurveMultiplierReductionCooldown(), 365 days);
    }

    function test_setCurveMultiplierReductionCooldown_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, additionalBondRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        additionalBondRegistry.setCurveMultiplierReductionCooldown(30 days);
    }

    function test_setCurveMultiplierReductionCooldown_RevertWhen_Zero() public {
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplierReductionCooldown.selector);
        vm.prank(admin);
        additionalBondRegistry.setCurveMultiplierReductionCooldown(0);
    }

    function test_setCurveMultiplierReductionCooldown_RevertWhen_ExceedsMax() public {
        vm.expectRevert(IAdditionalBondRegistry.InvalidCurveMultiplierReductionCooldown.selector);
        vm.prank(admin);
        additionalBondRegistry.setCurveMultiplierReductionCooldown(365 days + 1);
    }
}

contract AdditionalBondRegistryViewsTest is AdditionalBondRegistryRequestCurveMultiplierBaseTest {
    function setUp() public override {
        super.setUp();
        _setSteps();
    }

    function test_getSteps() public view {
        Step[] memory steps = additionalBondRegistry.getSteps();
        assertEq(steps.length, 2);
        assertEq(steps[0].threshold, T1_BOND);
        assertEq(steps[0].value, T1_WEIGHT);
    }

    function test_getWeightBoostMultiplierBP_Default() public view {
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_AfterUpgrade() public {
        vm.prank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND);
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);
    }

    function test_getWeightBoostMultiplierBP_BinarySearchBoundaries() public {
        uint256 curveStep = additionalBondRegistry.CURVE_MULTIPLIER_STEP();

        vm.startPrank(nodeOperatorOwner);
        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND - curveStep); // before first threshold
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP);

        additionalBondRegistry.requestCurveMultiplier(0, T1_BOND); // exactly first threshold
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);

        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND - curveStep); // between thresholds
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T1_WEIGHT);

        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND); // exactly final threshold
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T2_WEIGHT);

        additionalBondRegistry.requestCurveMultiplier(0, T2_BOND + curveStep); // after final threshold
        assertEq(additionalBondRegistry.getWeightBoostMultiplierBP(0), MAX_BP + T2_WEIGHT);
        vm.stopPrank();
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
