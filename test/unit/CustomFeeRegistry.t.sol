// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CustomFeeRegistry } from "src/CustomFeeRegistry.sol";
import { ICustomFeeRegistry, FeeModifier } from "src/interfaces/ICustomFeeRegistry.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IStepwiseWeightBoost, Step } from "src/interfaces/IStepwiseWeightBoost.sol";

import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { CuratedProviderFixture } from "../helpers/CuratedProviderFixture.sol";
import { StepwiseWeightBoostBehaviour } from "../helpers/StepwiseWeightBoostBehaviour.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract CustomFeeRegistryBaseTest is Test, Utilities, Fixtures, CuratedProviderFixture {
    CustomFeeRegistry public feeRegistry;
    AccountingMock internal _accounting;

    address public admin;
    address public nodeOperatorOwner;
    address public stranger;

    uint256 internal constant MAX_BP = 10_000;
    uint256 internal constant GRANULARITY = 250;
    uint256 internal constant BASE_FEE = 8_750;
    uint256 internal constant MAX_FEE_DISCOUNT = 6_250;
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
        feeRegistry.initialize(admin, MAX_FEE_DISCOUNT, COOLDOWN, _steps());

        _accounting = AccountingMock(address(module.ACCOUNTING()));
    }

    function _steps() internal pure returns (Step[] memory steps) {
        // Fee discount thresholds map to weight multiplier increments.
        steps = new Step[](4);
        steps[0] = Step({ threshold: 1_250, value: 2_000 });
        steps[1] = Step({ threshold: 2_500, value: 5_000 });
        steps[2] = Step({ threshold: 3_750, value: 10_000 });
        steps[3] = Step({ threshold: 6_250, value: 15_000 });
    }

    function _weight(uint256 discount) internal pure returns (uint256) {
        if (discount >= 6_250) return 25_000;
        if (discount >= 3_750) return 20_000;
        if (discount >= 2_500) return 15_000;
        if (discount >= 1_250) return 12_000;
        return MAX_BP;
    }

    function _requestFeeDiscount(uint256 discount) internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.requestFeeDiscount(NO_ID, discount);
    }

    function _applyFeeDiscountCut() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeDiscountCut(NO_ID);
    }

    function _cancelFeeDiscountCut() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.cancelFeeDiscountCut(NO_ID);
    }

    function _assertNoPendingFeeDiscountCut() internal view {
        assertEq(feeRegistry.getPendingFeeDiscount(NO_ID), 0);
        assertEq(feeRegistry.getFeeDiscountCutCooldownUntil(NO_ID), 0);
    }

    function _setFeeModifier(uint256 curveId, uint256 value, bool negative) internal {
        vm.prank(admin);
        feeRegistry.setFeeModifier(curveId, value, negative);
    }
}

contract CustomFeeRegistryConstructorTest is CustomFeeRegistryBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(feeRegistry.MODULE()), address(module));
        assertEq(address(feeRegistry.ACCOUNTING()), address(module.ACCOUNTING()));
        assertEq(address(feeRegistry.META_REGISTRY()), address(metaRegistryMock));
    }

    function test_constructor_Constants() public view {
        assertEq(feeRegistry.FEE_GRANULARITY(), GRANULARITY);
        assertEq(feeRegistry.BASE_FEE(), BASE_FEE);
        assertEq(feeRegistry.MAX_STEPS(), 35);
        assertEq(feeRegistry.MAX_STEP_VALUE(), 9 * MAX_BP);
        assertEq(feeRegistry.MAX_FEE_DISCOUNT_CUT_COOLDOWN(), 365 days);
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IStepwiseWeightBoost.ZeroModuleAddress.selector);
        new CustomFeeRegistry(address(0));
    }
}

contract CustomFeeRegistryInitializeTest is CustomFeeRegistryBaseTest {
    function _newRegistry() internal returns (CustomFeeRegistry registry) {
        registry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(registry));
    }

    function test_initialize() public view {
        assertTrue(feeRegistry.hasRole(feeRegistry.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(feeRegistry.getDefaultMaxFeeDiscount(), MAX_FEE_DISCOUNT);
        assertEq(feeRegistry.getFeeDiscountCutCooldown(), COOLDOWN);
        Step[] memory actual = feeRegistry.getSteps();
        Step[] memory expected = _steps();
        assertEq(actual.length, expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(actual[i].threshold, expected[i].threshold);
            assertEq(actual[i].value, expected[i].value);
        }
    }

    function test_initialize_EmitsEvents() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectEmit(address(registry));
        emit ICustomFeeRegistry.DefaultMaxFeeDiscountSet(MAX_FEE_DISCOUNT);
        vm.expectEmit(address(registry));
        emit ICustomFeeRegistry.FeeDiscountCutCooldownSet(COOLDOWN);
        vm.expectEmit(address(registry));
        emit IStepwiseWeightBoost.StepsSet(_steps());
        registry.initialize(admin, MAX_FEE_DISCOUNT, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(IStepwiseWeightBoost.ZeroAdminAddress.selector);
        registry.initialize(address(0), MAX_FEE_DISCOUNT, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeRegistry.initialize(admin, MAX_FEE_DISCOUNT, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroMaxFeeDiscount() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        registry.initialize(admin, 0, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_MaxFeeDiscountAtOrAboveBaseFee() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        registry.initialize(admin, BASE_FEE, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_MaxFeeDiscountNotGranularityAligned() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        registry.initialize(admin, MAX_FEE_DISCOUNT + 1, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroCooldown() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscountCutCooldown.selector);
        registry.initialize(admin, MAX_FEE_DISCOUNT, 0, _steps());
    }

    function test_initialize_RevertWhen_CooldownExceedsMax() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscountCutCooldown.selector);
        registry.initialize(admin, MAX_FEE_DISCOUNT, 365 days + 1, _steps());
    }
}

contract CustomFeeRegistryRequestFeeDiscountTest is CustomFeeRegistryBaseTest {
    function test_requestFeeDiscount_Raise_AppliesImmediately() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountSet(NO_ID, 3_750);
        _requestFeeDiscount(3_750);

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(3_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 1);
        assertEq(metaRegistryMock.lastChangedBoostOperatorId(), NO_ID);
    }

    function test_requestFeeDiscount_Raise_ToMaxFeeDiscount() public {
        _requestFeeDiscount(MAX_FEE_DISCOUNT);
        assertEq(feeRegistry.getFeeDiscount(NO_ID), MAX_FEE_DISCOUNT);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(MAX_FEE_DISCOUNT));
    }

    function test_requestFeeDiscount_Raise_DoesNotNotifyWhenStepValueUnchanged() public {
        _requestFeeDiscount(1_250);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFeeDiscount(1_500);

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_250));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFeeDiscount_Cut_SetsPending() public {
        _requestFeeDiscount(3_750);

        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutRequested(NO_ID, 2_750, cooldownUntil);
        _requestFeeDiscount(2_750);

        // The discount itself is unchanged, but the weight already follows the pending decrease.
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 2);
    }

    function test_requestFeeDiscount_Cut_OverwritesPendingAndRestartsCooldown() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);

        vm.warp(block.timestamp + 1 days);
        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutRequested(NO_ID, 1_750, cooldownUntil);
        _requestFeeDiscount(1_750);

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_750));

        // The old deadline is void: the decrease applies only at the restarted one.
        vm.warp(cooldownUntil - 1 days);
        vm.expectRevert(ICustomFeeRegistry.FeeDiscountCutCooldownNotElapsed.selector);
        _applyFeeDiscountCut();

        vm.warp(cooldownUntil);
        _applyFeeDiscountCut();
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_750);
    }

    function test_requestFeeDiscount_Cut_DoesNotNotifyWhenFeeDiscountBandUnchanged() public {
        _requestFeeDiscount(4_000);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFeeDiscount(3_750);

        assertEq(feeRegistry.getPendingFeeDiscount(NO_ID), 3_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(4_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFeeDiscount_Cut_OverwriteDoesNotNotifyWhenFeeDiscountBandUnchanged() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFeeDiscount(2_500);

        assertEq(feeRegistry.getPendingFeeDiscount(NO_ID), 2_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFeeDiscount_Cut_RaisingPendingRaisesWeight() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(1_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_750));

        _requestFeeDiscount(2_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_750));
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
    }

    function test_requestFeeDiscount_Raise_CancelsPending() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutCancelled(NO_ID);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountSet(NO_ID, 4_750);
        _requestFeeDiscount(4_750);

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 4_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(4_750));

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.expectRevert(ICustomFeeRegistry.NoPendingFeeDiscountCut.selector);
        _applyFeeDiscountCut();
    }

    function test_requestFeeDiscount_RevertWhen_NotOwner() public {
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.requestFeeDiscount(NO_ID, 3_750);
    }

    function test_requestFeeDiscount_RevertWhen_AboveMaxFeeDiscount() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _requestFeeDiscount(MAX_FEE_DISCOUNT + GRANULARITY);
    }

    function test_requestFeeDiscount_RevertWhen_NotGranularityAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _requestFeeDiscount(3_750 + 1);
    }

    function test_requestFeeDiscount_RevertWhen_AboveTypeCeiling() public {
        _setFeeModifier(0, 2_500, true);
        // The negative modifier lowers the operator's discount ceiling to 3_750.
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _requestFeeDiscount(4_000);
    }

    function test_requestFeeDiscount_RevertWhen_SameFeeDiscount_Unset() public {
        vm.expectRevert(ICustomFeeRegistry.SameFeeDiscount.selector);
        _requestFeeDiscount(0);
    }

    function test_requestFeeDiscount_RevertWhen_SameFeeDiscount_Set() public {
        _requestFeeDiscount(3_750);
        vm.expectRevert(ICustomFeeRegistry.SameFeeDiscount.selector);
        _requestFeeDiscount(3_750);
    }

    function test_requestFeeDiscount_RevertWhen_SameFeeDiscountWithPendingCut() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);

        vm.expectRevert(ICustomFeeRegistry.SameFeeDiscount.selector);
        _requestFeeDiscount(3_750);
    }
}

contract CustomFeeRegistryCancelFeeDiscountCutTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);
    }

    function test_cancelFeeDiscountCut() public {
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutCancelled(NO_ID);
        _cancelFeeDiscountCut();

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
        _assertNoPendingFeeDiscountCut();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(3_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_cancelFeeDiscountCut_AfterCooldown() public {
        vm.warp(block.timestamp + COOLDOWN + 1);
        _cancelFeeDiscountCut();
        _assertNoPendingFeeDiscountCut();
    }

    function test_cancelFeeDiscountCut_DoesNotNotifyWhenFeeDiscountBandUnchanged() public {
        _cancelFeeDiscountCut();
        _requestFeeDiscount(4_000);
        _requestFeeDiscount(3_750);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _cancelFeeDiscountCut();

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 4_000);
        _assertNoPendingFeeDiscountCut();
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_cancelFeeDiscountCut_WhenCurrentFeeDiscountAboveNewCeiling() public {
        _setFeeModifier(0, 4_000, true); // The new ceiling is 2_250.
        _cancelFeeDiscountCut();

        _assertNoPendingFeeDiscountCut();
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 3_750);
    }

    function test_cancelFeeDiscountCut_RevertWhen_NotOwner() public {
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.cancelFeeDiscountCut(NO_ID);
    }

    function test_cancelFeeDiscountCut_RevertWhen_NoPendingCut() public {
        _cancelFeeDiscountCut();
        vm.expectRevert(ICustomFeeRegistry.NoPendingFeeDiscountCut.selector);
        _cancelFeeDiscountCut();
    }
}

contract CustomFeeRegistryApplyFeeDiscountCutTest is CustomFeeRegistryBaseTest {
    uint256 internal cooldownUntil;

    function setUp() public override {
        super.setUp();
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);
        cooldownUntil = block.timestamp + COOLDOWN;
    }

    function test_applyFeeDiscountCut() public {
        vm.warp(cooldownUntil + 1);

        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutApplied(NO_ID, 2_750);
        _applyFeeDiscountCut();

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 2_750);
        // The weight followed the pending discount already, so no new notification.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_applyFeeDiscountCut_AtExactDeadline() public {
        vm.warp(cooldownUntil);
        _applyFeeDiscountCut();
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 2_750);
    }

    function test_applyFeeDiscountCut_CooldownChangeDoesNotAffectPending() public {
        vm.prank(admin);
        feeRegistry.setFeeDiscountCutCooldown(COOLDOWN * 2);

        vm.warp(cooldownUntil);
        _applyFeeDiscountCut();
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 2_750);
    }

    function test_applyFeeDiscountCut_PendingSurvivesAnInvalidatingModifier() public {
        _setFeeModifier(0, 4_000, true); // The new ceiling is 2_250, the pending discount is 2_750.
        vm.warp(cooldownUntil);

        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _applyFeeDiscountCut();

        // The pending discount is untouched and applies once the ceiling allows it again.
        _setFeeModifier(0, 2_500, true);
        _applyFeeDiscountCut();
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 2_750);
    }

    function test_applyFeeDiscountCut_InvalidPendingCanBeNormalizedPermissionlessly() public {
        _setFeeModifier(0, 4_000, true); // The new ceiling is 2_250, the pending discount is 2_750.
        vm.warp(cooldownUntil);

        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _applyFeeDiscountCut();

        vm.prank(stranger);
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 2_250);
        _assertNoPendingFeeDiscountCut();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(2_250));
    }

    function test_applyFeeDiscountCut_RevertWhen_NotOwner() public {
        vm.warp(cooldownUntil + 1);
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.applyFeeDiscountCut(NO_ID);
    }

    function test_applyFeeDiscountCut_RevertWhen_NotElapsed() public {
        vm.warp(cooldownUntil - 1);
        vm.expectRevert(ICustomFeeRegistry.FeeDiscountCutCooldownNotElapsed.selector);
        _applyFeeDiscountCut();
    }

    function test_applyFeeDiscountCut_RevertWhen_NoPending() public {
        vm.warp(cooldownUntil + 1);
        _applyFeeDiscountCut();

        vm.expectRevert(ICustomFeeRegistry.NoPendingFeeDiscountCut.selector);
        _applyFeeDiscountCut();
    }
}

contract CustomFeeRegistryNormalizeFeeDiscountsTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();

        // Operator 0 is left above the new ceiling; the other operators remain unset and valid.
        _setFeeModifier(0, 2_500, true);
        _requestFeeDiscount(3_750);
        _setFeeModifier(0, 5_000, true);
    }

    function test_normalizeFeeDiscounts() public {
        uint256 normalizedCount = feeRegistry.normalizeFeeDiscounts(UintArr(0, 1, 2));

        assertEq(normalizedCount, 1);
        assertEq(feeRegistry.getFeeDiscount(0), 1_250);
        assertEq(feeRegistry.getFeeDiscount(1), 0);
        assertEq(feeRegistry.getFeeDiscount(2), 0);
    }

    function test_normalizeFeeDiscounts_SetsFeeDiscountToCeilingAndRestoresEffectiveFee() public {
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 0); // max(0, 5_000 - 5_000)

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountSet(NO_ID, 1_250);
        vm.prank(stranger); // permissionless
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_250);
        // The effective fee is back at the floor implied by the default discount ceiling.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), BASE_FEE - MAX_FEE_DISCOUNT);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_250));
    }

    function test_normalizeFeeDiscounts_ClampsToZeroWhenTypeGrantsNoDiscount() public {
        _setFeeModifier(0, MAX_FEE_DISCOUNT, true); // The ceiling drops to zero.

        vm.prank(stranger);
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 0);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);
    }

    function test_normalizeFeeDiscounts_CancelsPendingCut() public {
        _requestFeeDiscount(750);

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutCancelled(NO_ID);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountSet(NO_ID, 1_250);
        vm.prank(stranger);
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_250);
        _assertNoPendingFeeDiscountCut();
    }

    function test_normalizeFeeDiscounts_CancelsExpiredPendingCut() public {
        _requestFeeDiscount(750);
        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(stranger);
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_250);
        _assertNoPendingFeeDiscountCut();
    }

    function test_normalizeFeeDiscounts_DoesNotNotifyWhenPendingFeeDiscountEqualsCeiling() public {
        _requestFeeDiscount(1_250);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(stranger);
        feeRegistry.normalizeFeeDiscounts(UintArr(NO_ID));

        assertEq(feeRegistry.getFeeDiscount(NO_ID), 1_250);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_normalizeFeeDiscounts_SkipsDuplicatesAndValidOperators() public {
        uint256[] memory nodeOperatorIds = new uint256[](4);
        nodeOperatorIds[0] = 0;
        nodeOperatorIds[1] = 0;
        nodeOperatorIds[2] = 2;
        nodeOperatorIds[3] = 1;
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        uint256 normalizedCount = feeRegistry.normalizeFeeDiscounts(nodeOperatorIds);

        assertEq(normalizedCount, 1);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_normalizeFeeDiscounts_EmptyArray() public {
        uint256 normalizedCount = feeRegistry.normalizeFeeDiscounts(UintArr());
        assertEq(normalizedCount, 0);
    }

    function test_normalizeFeeDiscounts_NoFeeDiscountsToNormalize() public {
        uint256[] memory nodeOperatorIds = UintArr(0, 1);
        feeRegistry.normalizeFeeDiscounts(nodeOperatorIds);

        uint256 normalizedCount = feeRegistry.normalizeFeeDiscounts(nodeOperatorIds);

        assertEq(normalizedCount, 0);
    }
}

contract CustomFeeRegistrySetDefaultMaxFeeDiscountTest is CustomFeeRegistryBaseTest {
    function test_setDefaultMaxFeeDiscount() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.DefaultMaxFeeDiscountSet(6_500);
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(6_500);

        assertEq(feeRegistry.getDefaultMaxFeeDiscount(), 6_500);
    }

    function test_setDefaultMaxFeeDiscount_UsesLastWeightStepAboveLastThreshold() public {
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(7_750);

        _requestFeeDiscount(7_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_750));
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 25_000);
    }

    function test_setDefaultMaxFeeDiscount_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setDefaultMaxFeeDiscount(6_500);
    }

    function test_setDefaultMaxFeeDiscount_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(0);
    }

    function test_setDefaultMaxFeeDiscount_RevertWhen_NotAboveCurrent() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(MAX_FEE_DISCOUNT);
    }

    function test_setDefaultMaxFeeDiscount_RevertWhen_AtOrAboveBaseFee() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(BASE_FEE);
    }

    function test_setDefaultMaxFeeDiscount_RevertWhen_NotGranularityAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMaxFeeDiscount.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(6_500 + 1);
    }
}

contract CustomFeeRegistrySetFeeModifierTest is CustomFeeRegistryBaseTest {
    function test_setFeeModifier_Positive() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeModifierSet(0, 1_250, false);
        _setFeeModifier(0, 1_250, false);

        FeeModifier memory feeModifier = feeRegistry.getFeeModifier(0);
        assertEq(feeModifier.value, 1_250);
        assertFalse(feeModifier.negative);
        // The modifier tops the effective fee up to 100% for an operator without a discount.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_BP);
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), MAX_FEE_DISCOUNT);
    }

    function test_setFeeModifier_Negative() public {
        _setFeeModifier(0, 2_500, true);

        FeeModifier memory feeModifier = feeRegistry.getFeeModifier(0);
        assertEq(feeModifier.value, 2_500);
        assertTrue(feeModifier.negative);
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), MAX_FEE_DISCOUNT - 2_500);
    }

    function test_setFeeModifier_NegativeAtDefaultCeilingLeavesNoDiscount() public {
        _setFeeModifier(0, MAX_FEE_DISCOUNT, true);

        // The ceiling is exactly zero: the type grants no discount at all.
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), 0);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), BASE_FEE - MAX_FEE_DISCOUNT);

        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscount.selector);
        _requestFeeDiscount(GRANULARITY);
    }

    function test_setFeeModifier_NegativeAtDefaultCeilingSurvivesCeilingRaise() public {
        _setFeeModifier(0, MAX_FEE_DISCOUNT, true);

        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(MAX_FEE_DISCOUNT + GRANULARITY);

        // The default ceiling only ever grows, so the per-type ceiling can only widen from zero.
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), GRANULARITY);
        _requestFeeDiscount(GRANULARITY);
        assertEq(feeRegistry.getFeeDiscount(NO_ID), GRANULARITY);
    }

    function test_setFeeModifier_ZeroWithAnySign() public {
        _setFeeModifier(0, 0, true);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), BASE_FEE);
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), MAX_FEE_DISCOUNT);

        _setFeeModifier(0, 0, false);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), BASE_FEE);
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), MAX_FEE_DISCOUNT);
    }

    function test_setFeeModifier_DoesNotNotifyAndDoesNotMoveWeight() public {
        _requestFeeDiscount(3_750);
        uint256 weightBefore = feeRegistry.getWeightBoostMultiplierBP(NO_ID);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _setFeeModifier(0, 1_250, false);

        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), weightBefore);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_setFeeModifier_SameFeeDiscountSameWeightAcrossTypes() public {
        _setFeeModifier(0, 1_250, false);
        _accounting.setBondCurve(1, 1); // Add curve 1 without moving NO_ID from curve 0.
        _setFeeModifier(1, 2_500, true);
        _requestFeeDiscount(3_750);

        uint256 weightOnTypeA = feeRegistry.getWeightBoostMultiplierBP(NO_ID);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 6_250);

        // Moving the operator to another type shifts only the effective fee, never the weight.
        _accounting.setBondCurve(NO_ID, 1);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), weightOnTypeA);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 2_500);
    }

    function test_setFeeModifier_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setFeeModifier(0, 1_250, false);
    }

    function test_setFeeModifier_RevertWhen_PositiveAboveMax() public {
        // MAX_BP - BASE_FEE = 1_250 is the largest positive modifier.
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeModifier.selector);
        _setFeeModifier(0, 1_250 + GRANULARITY, false);
    }

    function test_setFeeModifier_RevertWhen_NegativeAboveMax() public {
        // The default discount ceiling is the largest negative modifier.
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeModifier.selector);
        _setFeeModifier(0, MAX_FEE_DISCOUNT + GRANULARITY, true);
    }

    function test_setFeeModifier_RevertWhen_NotGranularityAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeModifier.selector);
        _setFeeModifier(0, 100, false);
    }

    function test_setFeeModifier_RevertWhen_CurveDoesNotExist() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        _setFeeModifier(1, 0, false);
    }
}

contract CustomFeeRegistrySetStepsTest is CustomFeeRegistryBaseTest, StepwiseWeightBoostBehaviour {
    function _setSteps(Step[] memory steps) internal {
        vm.prank(admin);
        feeRegistry.setSteps(steps);
    }

    function _stepwise() internal view override returns (IStepwiseWeightBoost) {
        return IStepwiseWeightBoost(address(feeRegistry));
    }

    function _stepwiseAdmin() internal view override returns (address) {
        return admin;
    }

    function _stepwiseSteps(uint256 count) internal view override returns (Step[] memory steps) {
        steps = new Step[](count);
        for (uint256 i; i < count; ++i) {
            // Fee discounts are FEE_GRANULARITY-aligned and stay below BASE_FEE.
            steps[i] = Step({ threshold: uint128(i * GRANULARITY), value: uint128((i + 1) * 100) });
        }
    }

    function test_setSteps_ReplacesStepsAndNotifies() public {
        // Fee discount thresholds map to weight multiplier increments.
        Step[] memory steps = new Step[](2);
        steps[0] = Step({ threshold: 0, value: 0 });
        steps[1] = Step({ threshold: 5_000, value: 9_000 });

        vm.expectEmit(address(feeRegistry));
        emit IStepwiseWeightBoost.StepsSet(steps);
        _setSteps(steps);

        Step[] memory stored = feeRegistry.getSteps();
        assertEq(stored.length, 2);
        assertEq(stored[0].threshold, 0);
        assertEq(stored[0].value, 0);
        assertEq(stored[1].threshold, 5_000);
        assertEq(stored[1].value, 9_000);
        assertEq(metaRegistryMock.notifyWeightBoostProviderConfigChangedCallCount(), 1);
    }

    function test_setSteps_ChangesFeeDiscountWeights() public {
        _requestFeeDiscount(3_750);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 20_000);

        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 3_750, value: 7_000 });
        _setSteps(steps);

        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 17_000);
    }

    function test_setSteps_AllowsMaximumValues() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(BASE_FEE - GRANULARITY), value: uint128(feeRegistry.MAX_STEP_VALUE()) });
        _setSteps(steps);

        assertEq(feeRegistry.getSteps()[0].threshold, BASE_FEE - GRANULARITY);
    }

    function test_setSteps_RevertWhen_FeeDiscountAtBaseFee() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(BASE_FEE), value: 1 });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }

    function test_setSteps_RevertWhen_FeeDiscountNotAligned() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 1, value: 1 });
        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        _setSteps(steps);
    }
}

contract CustomFeeRegistrySetFeeDiscountCutCooldownTest is CustomFeeRegistryBaseTest {
    function test_setFeeDiscountCutCooldown() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeDiscountCutCooldownSet(30 days);
        vm.prank(admin);
        feeRegistry.setFeeDiscountCutCooldown(30 days);

        assertEq(feeRegistry.getFeeDiscountCutCooldown(), 30 days);
    }

    function test_setFeeDiscountCutCooldown_Max() public {
        vm.prank(admin);
        feeRegistry.setFeeDiscountCutCooldown(365 days);

        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);

        assertEq(feeRegistry.getFeeDiscountCutCooldown(), 365 days);
        assertEq(feeRegistry.getFeeDiscountCutCooldownUntil(NO_ID), block.timestamp + 365 days);
    }

    function test_setFeeDiscountCutCooldown_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setFeeDiscountCutCooldown(30 days);
    }

    function test_setFeeDiscountCutCooldown_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscountCutCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeDiscountCutCooldown(0);
    }

    function test_setFeeDiscountCutCooldown_RevertWhen_ExceedsMax() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeDiscountCutCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeDiscountCutCooldown(365 days + 1);
    }
}

contract CustomFeeRegistryViewsTest is CustomFeeRegistryBaseTest {
    function test_getFeeDiscount_UnsetIsZero() public view {
        assertEq(feeRegistry.getFeeDiscount(NO_ID), 0);
    }

    function test_getPendingFeeDiscountAndCooldownUntil() public {
        assertEq(feeRegistry.getPendingFeeDiscount(NO_ID), 0);
        assertEq(feeRegistry.getFeeDiscountCutCooldownUntil(NO_ID), 0);

        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);

        assertEq(feeRegistry.getPendingFeeDiscount(NO_ID), 2_750);
        assertEq(feeRegistry.getFeeDiscountCutCooldownUntil(NO_ID), block.timestamp + COOLDOWN);
    }

    function test_getWeightBoostMultiplierBP_UnsetIsOne() public view {
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_StepsAndBands() public {
        _requestFeeDiscount(GRANULARITY);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);

        _requestFeeDiscount(1_250);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 12_000);

        _requestFeeDiscount(1_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 12_000);

        _requestFeeDiscount(MAX_FEE_DISCOUNT);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 25_000);
    }

    function test_getWeightBoostMultiplierBP_BinarySearchAtMaxSteps() public {
        uint256 stepsCount = feeRegistry.MAX_STEPS();
        Step[] memory steps = new Step[](stepsCount);
        for (uint256 i; i < stepsCount; ++i) {
            steps[i] = Step({ threshold: uint128(i * GRANULARITY), value: uint128(i * 1_000) });
        }
        vm.prank(admin);
        feeRegistry.setSteps(steps);

        _requestFeeDiscount(4_250); // Reaches step 17.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 17_000);

        vm.prank(admin);
        feeRegistry.setDefaultMaxFeeDiscount(BASE_FEE - GRANULARITY);
        _requestFeeDiscount(BASE_FEE - GRANULARITY); // Reaches the final step 34.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 34_000);
    }

    function test_getEffectiveFee_NoModifier() public {
        _requestFeeDiscount(3_750);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 5_000);
    }

    function test_getEffectiveFee_ClampsAtZero() public {
        _setFeeModifier(0, 2_500, true);
        _requestFeeDiscount(3_750);
        _setFeeModifier(0, 5_500, true);

        assertEq(feeRegistry.getEffectiveFee(NO_ID), 0);
    }

    function test_getEffectiveFee_PendingCutIsExcluded() public {
        _requestFeeDiscount(3_750);
        _requestFeeDiscount(2_750);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 5_000);
    }

    function test_getMaxFeeDiscount_Default() public view {
        assertEq(feeRegistry.getMaxFeeDiscount(NO_ID), MAX_FEE_DISCOUNT);
    }
}
