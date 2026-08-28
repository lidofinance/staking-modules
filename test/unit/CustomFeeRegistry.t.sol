// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CustomFeeRegistry } from "src/CustomFeeRegistry.sol";
import { ICustomFeeRegistry } from "src/interfaces/ICustomFeeRegistry.sol";
import { IBaseWeightBoostProvider } from "src/interfaces/IBaseWeightBoostProvider.sol";
import { IStepwiseWeightBoost, Step } from "src/interfaces/IStepwiseWeightBoost.sol";

import { CuratedProviderFixture } from "../helpers/CuratedProviderFixture.sol";
import { StepwiseWeightBoostBehaviour } from "../helpers/StepwiseWeightBoostBehaviour.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract CustomFeeRegistryBaseTest is Test, Utilities, Fixtures, CuratedProviderFixture {
    CustomFeeRegistry public feeRegistry;

    address public admin;
    address public nodeOperatorOwner;
    address public stranger;

    uint256 internal constant MAX_BP = 10_000;
    uint256 internal constant COOLDOWN = 15 days;
    uint256 internal constant NO_ID = 0;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        stranger = nextAddress("STRANGER");

        _deployModuleWithMetaRegistryMock(3);
        _setNodeOperatorOwner(nodeOperatorOwner);

        feeRegistry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(feeRegistry));
        feeRegistry.initialize(admin, COOLDOWN, _exampleSteps());
    }

    function _exampleSteps() internal pure returns (Step[] memory steps) {
        // Fee share discount thresholds map to weight multiplier increments.
        steps = new Step[](4);
        steps[0] = Step({ threshold: 1_200, value: 2_000 });
        steps[1] = Step({ threshold: 2_500, value: 5_000 });
        steps[2] = Step({ threshold: 3_700, value: 10_000 });
        steps[3] = Step({ threshold: 6_200, value: 15_000 });
    }

    function _weight(uint256 feeShareDiscount) internal pure returns (uint256) {
        if (feeShareDiscount >= 6_200) return 25_000;
        if (feeShareDiscount >= 3_700) return 20_000;
        if (feeShareDiscount >= 2_500) return 15_000;
        if (feeShareDiscount >= 1_200) return 12_000;
        return MAX_BP;
    }

    function _requestFeeShareDiscount(uint256 feeShareDiscount) internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.requestFeeShareDiscount(NO_ID, feeShareDiscount);
    }

    function _applyFeeShareDiscountCut() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeShareDiscountCut(NO_ID);
    }

    function _cancelFeeShareDiscountCut() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.cancelFeeShareDiscountCut(NO_ID);
    }

    function _assertNoPendingFeeShareDiscountCut() internal view {
        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).pendingFeeShareDiscount, 0);
        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).cooldownUntil, 0);
    }
}

contract CustomFeeRegistryConstructorTest is CustomFeeRegistryBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(feeRegistry.MODULE()), address(module));
        assertEq(address(feeRegistry.META_REGISTRY()), address(metaRegistryMock));
    }

    function test_constructor_Constants() public view {
        assertEq(feeRegistry.FEE_SHARE_DISCOUNT_STEP(), 100);
        assertEq(feeRegistry.MAX_STEPS(), 35);
        assertEq(feeRegistry.MAX_STEP_VALUE(), 9 * MAX_BP);
        assertEq(feeRegistry.MAX_FEE_SHARE_DISCOUNT_CUT_COOLDOWN(), 365 days);
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IBaseWeightBoostProvider.ZeroModuleAddress.selector);
        new CustomFeeRegistry(address(0));
    }
}

contract CustomFeeRegistryInitializeTest is CustomFeeRegistryBaseTest {
    function test_initialize_SetsAdmin() public view {
        assertTrue(feeRegistry.hasRole(feeRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_SetsCooldown() public view {
        assertEq(feeRegistry.getFeeShareDiscountCutCooldown(), COOLDOWN);
    }

    function test_initialize_SetsSteps() public view {
        Step[] memory stored = feeRegistry.getSteps();
        assertEq(stored.length, 4);
        assertEq(stored[0].threshold, 1_200);
        assertEq(stored[3].value, 15_000);
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        CustomFeeRegistry registry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(registry));
        vm.expectRevert(IBaseWeightBoostProvider.ZeroAdminAddress.selector);
        registry.initialize(address(0), COOLDOWN, new Step[](0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeRegistry.initialize(admin, COOLDOWN, _exampleSteps());
    }

    function test_initialize_RevertWhen_ZeroCooldown() public {
        CustomFeeRegistry registry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(registry));
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscountCutCooldown.selector);
        registry.initialize(admin, 0, new Step[](0));
    }

    function test_initialize_RevertWhen_CooldownExceedsMax() public {
        CustomFeeRegistry registry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(registry));
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscountCutCooldown.selector);
        registry.initialize(admin, 365 days + 1, new Step[](0));
    }

    function test_initialize_RevertWhen_EmptySteps() public {
        CustomFeeRegistry registry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(registry));
        vm.expectRevert(IStepwiseWeightBoost.InvalidStepCount.selector);
        registry.initialize(admin, COOLDOWN, new Step[](0));
    }
}

contract CustomFeeRegistryRequestFeeShareDiscountTest is CustomFeeRegistryBaseTest {
    function test_requestFeeShareDiscount_Increase_AppliesImmediately() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountSet(NO_ID, 3_700);
        _requestFeeShareDiscount(3_700);

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 3_700);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(3_700));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 1);
        assertEq(metaRegistryMock.lastChangedBoostOperatorId(), NO_ID);
    }

    function test_requestFeeShareDiscount_Increase_ToMaximum() public {
        _requestFeeShareDiscount(10_000);
        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 10_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(10_000));
    }

    function test_requestFeeShareDiscount_Increase_DoesNotNotifyWithinSameBand() public {
        _requestFeeShareDiscount(1_200);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        _requestFeeShareDiscount(1_500);

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 1_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_200));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFeeShareDiscount_Cut_SetsPendingAndMovesWeightImmediately() public {
        _requestFeeShareDiscount(3_700);
        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountCutRequested(NO_ID, 2_700, cooldownUntil);
        _requestFeeShareDiscount(2_700);

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 3_700);
        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).pendingFeeShareDiscount, 2_700);
        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).cooldownUntil, cooldownUntil);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_700));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 2);
    }

    function test_requestFeeShareDiscount_Cut_OverwritesPendingAndRestartsCooldown() public {
        _requestFeeShareDiscount(3_700);
        _requestFeeShareDiscount(2_700);
        vm.warp(block.timestamp + 1 days);
        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        _requestFeeShareDiscount(1_700);

        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).pendingFeeShareDiscount, 1_700);
        assertEq(feeRegistry.getFeeShareDiscountState(NO_ID).cooldownUntil, cooldownUntil);
        vm.warp(cooldownUntil - 1);
        vm.expectRevert(ICustomFeeRegistry.FeeShareDiscountCutCooldownNotElapsed.selector);
        _applyFeeShareDiscountCut();
    }

    function test_requestFeeShareDiscount_Increase_CancelsPendingCut() public {
        _requestFeeShareDiscount(3_700);
        _requestFeeShareDiscount(2_700);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountCutCancelled(NO_ID);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountSet(NO_ID, 4_700);
        _requestFeeShareDiscount(4_700);

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 4_700);
        _assertNoPendingFeeShareDiscountCut();
    }

    function test_requestFeeShareDiscount_RevertWhen_NotOwner() public {
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.requestFeeShareDiscount(NO_ID, 3_700);
    }

    function test_requestFeeShareDiscount_RevertWhen_AboveMaximum() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscount.selector);
        _requestFeeShareDiscount(10_100);
    }

    function test_requestFeeShareDiscount_RevertWhen_SameFeeShareDiscount_Unset() public {
        vm.expectRevert(ICustomFeeRegistry.SameFeeShareDiscount.selector);
        _requestFeeShareDiscount(0);
    }

    function test_requestFeeShareDiscount_RevertWhen_NotAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscount.selector);
        _requestFeeShareDiscount(3_701);
    }

    function test_requestFeeShareDiscount_RevertWhen_SameFeeShareDiscount() public {
        _requestFeeShareDiscount(3_700);
        vm.expectRevert(ICustomFeeRegistry.SameFeeShareDiscount.selector);
        _requestFeeShareDiscount(3_700);
    }
}

contract CustomFeeRegistryCancelFeeShareDiscountCutTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();
        _requestFeeShareDiscount(3_700);
        _requestFeeShareDiscount(2_700);
    }

    function test_cancelFeeShareDiscountCut() public {
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountCutCancelled(NO_ID);
        _cancelFeeShareDiscountCut();

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 3_700);
        _assertNoPendingFeeShareDiscountCut();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(3_700));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_cancelFeeShareDiscountCut_RevertWhen_NotOwner() public {
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.cancelFeeShareDiscountCut(NO_ID);
    }

    function test_cancelFeeShareDiscountCut_RevertWhen_None() public {
        _cancelFeeShareDiscountCut();
        vm.expectRevert(ICustomFeeRegistry.NoPendingFeeShareDiscountCut.selector);
        _cancelFeeShareDiscountCut();
    }
}

contract CustomFeeRegistryApplyFeeShareDiscountCutTest is CustomFeeRegistryBaseTest {
    uint256 internal cooldownUntil;

    function setUp() public override {
        super.setUp();
        _requestFeeShareDiscount(3_700);
        _requestFeeShareDiscount(2_700);
        cooldownUntil = block.timestamp + COOLDOWN;
    }

    function test_applyFeeShareDiscountCut_AtExactDeadline() public {
        vm.warp(cooldownUntil);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountCutApplied(NO_ID, 2_700);
        _applyFeeShareDiscountCut();

        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 2_700);
        _assertNoPendingFeeShareDiscountCut();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_700));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_applyFeeShareDiscountCut_CooldownChangeDoesNotAffectPending() public {
        vm.prank(admin);
        feeRegistry.setFeeShareDiscountCutCooldown(COOLDOWN * 2);
        vm.warp(cooldownUntil);
        _applyFeeShareDiscountCut();
        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 2_700);
    }

    function test_applyFeeShareDiscountCut_RevertWhen_NotElapsed() public {
        vm.warp(cooldownUntil - 1);
        vm.expectRevert(ICustomFeeRegistry.FeeShareDiscountCutCooldownNotElapsed.selector);
        _applyFeeShareDiscountCut();
    }

    function test_applyFeeShareDiscountCut_RevertWhen_NotOwner() public {
        vm.warp(cooldownUntil);
        vm.expectRevert(IBaseWeightBoostProvider.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.applyFeeShareDiscountCut(NO_ID);
    }

    function test_applyFeeShareDiscountCut_RevertWhen_None() public {
        vm.warp(cooldownUntil);
        _applyFeeShareDiscountCut();
        vm.expectRevert(ICustomFeeRegistry.NoPendingFeeShareDiscountCut.selector);
        _applyFeeShareDiscountCut();
    }
}

contract CustomFeeRegistrySetStepsTest is CustomFeeRegistryBaseTest, StepwiseWeightBoostBehaviour {
    function _stepwise() internal view override returns (IStepwiseWeightBoost) {
        return IStepwiseWeightBoost(address(feeRegistry));
    }

    function _stepwiseAdmin() internal view override returns (address) {
        return admin;
    }

    function _stepwiseSteps(uint256 count) internal pure override returns (Step[] memory steps) {
        steps = new Step[](count);
        for (uint256 i; i < count; ++i) {
            steps[i] = Step({ threshold: uint128(i * 100), value: uint128((i + 1) * 100) });
        }
    }

    function _setSteps(Step[] memory steps) internal {
        vm.prank(admin);
        feeRegistry.setSteps(steps);
    }

    function test_setSteps_ChangesWeights() public {
        _requestFeeShareDiscount(3_700);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 20_000);

        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 3_700, value: 7_000 });
        _setSteps(steps);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 17_000);
    }

    function test_setSteps_AllowsMaxThreshold() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 10_000, value: uint128(feeRegistry.MAX_STEP_VALUE()) });
        _setSteps(steps);
        assertEq(feeRegistry.getSteps()[0].threshold, 10_000);
    }

    function test_setSteps_RevertWhen_ThresholdAboveMaxBP() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 10_100, value: 1 });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }

    function test_setSteps_RevertWhen_ThresholdNotStepAligned() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 1, value: 1 });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }
}

contract CustomFeeRegistrySetFeeShareDiscountCutCooldownTest is CustomFeeRegistryBaseTest {
    function test_setFeeShareDiscountCutCooldown() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeShareDiscountCutCooldownSet(30 days);
        vm.prank(admin);
        feeRegistry.setFeeShareDiscountCutCooldown(30 days);
        assertEq(feeRegistry.getFeeShareDiscountCutCooldown(), 30 days);
    }

    function test_setFeeShareDiscountCutCooldown_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setFeeShareDiscountCutCooldown(30 days);
    }

    function test_setFeeShareDiscountCutCooldown_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscountCutCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeShareDiscountCutCooldown(0);
    }

    function test_setFeeShareDiscountCutCooldown_RevertWhen_ExceedsMax() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeShareDiscountCutCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeShareDiscountCutCooldown(365 days + 1);
    }
}

contract CustomFeeRegistryViewsTest is CustomFeeRegistryBaseTest {
    function test_getFeeShareDiscount_UnsetIsZero() public view {
        assertEq(feeRegistry.getFeeShareDiscount(NO_ID), 0);
    }

    function test_getWeightBoostMultiplierBP_UnsetIsOne() public view {
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_StepsAndBands() public {
        _requestFeeShareDiscount(1_200);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 12_000);
        _requestFeeShareDiscount(2_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 15_000);
        _requestFeeShareDiscount(3_700);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 20_000);
        _requestFeeShareDiscount(10_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(10_000));
    }

    function test_getWeightBoostMultiplierBP_BinarySearchAtMaxSteps() public {
        uint256 stepsCount = feeRegistry.MAX_STEPS();
        Step[] memory steps = new Step[](stepsCount);
        for (uint256 i; i < stepsCount; ++i) {
            steps[i] = Step({ threshold: uint128(i * 100), value: uint128(i * 1_000) });
        }
        vm.prank(admin);
        feeRegistry.setSteps(steps);

        _requestFeeShareDiscount(1_700); // Reaches step 17.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 17_000);
        _requestFeeShareDiscount(3_400); // Reaches the final step 34.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 34_000);
    }
}
