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
    uint256 internal constant STEP = 250;
    uint256 internal constant MAX_FEE = 8_750;
    uint256 internal constant MIN_FEE = 2_500;
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
        feeRegistry.initialize(admin, MIN_FEE, COOLDOWN, _steps());

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

    function _weight(uint256 fee) internal pure returns (uint256) {
        uint256 discount = MAX_FEE - fee;
        if (discount >= 6_250) return 25_000;
        if (discount >= 3_750) return 20_000;
        if (discount >= 2_500) return 15_000;
        if (discount >= 1_250) return 12_000;
        return MAX_BP;
    }

    function _requestFee(uint256 fee) internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.requestFee(NO_ID, fee);
    }

    function _applyFeeIncrease() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
    }

    function _cancelFeeIncrease() internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.cancelFeeIncrease(NO_ID);
    }

    function _assertNoPendingFeeIncrease() internal view {
        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 0);
        assertEq(feeRegistry.getFeeIncreaseCooldownUntil(NO_ID), 0);
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
        assertEq(feeRegistry.FEE_STEP(), STEP);
        assertEq(feeRegistry.DEFAULT_MAX_FEE(), MAX_FEE);
        assertEq(feeRegistry.MAX_STEPS(), 35);
        assertEq(feeRegistry.MAX_STEP_VALUE(), 9 * MAX_BP);
        assertEq(feeRegistry.MAX_FEE_INCREASE_COOLDOWN(), 365 days);
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
        assertEq(feeRegistry.getDefaultMinFee(), MIN_FEE);
        assertEq(feeRegistry.getFeeIncreaseCooldown(), COOLDOWN);
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
        emit ICustomFeeRegistry.DefaultMinFeeSet(MIN_FEE);
        vm.expectEmit(address(registry));
        emit ICustomFeeRegistry.FeeIncreaseCooldownSet(COOLDOWN);
        vm.expectEmit(address(registry));
        emit IStepwiseWeightBoost.StepsSet(_steps());
        registry.initialize(admin, MIN_FEE, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(IStepwiseWeightBoost.ZeroAdminAddress.selector);
        registry.initialize(address(0), MIN_FEE, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeRegistry.initialize(admin, MIN_FEE, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroMinFee() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        registry.initialize(admin, 0, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_MinFeeAtOrAboveMax() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        registry.initialize(admin, MAX_FEE, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_MinFeeNotStepAligned() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        registry.initialize(admin, MIN_FEE + 1, COOLDOWN, _steps());
    }

    function test_initialize_RevertWhen_ZeroCooldown() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        registry.initialize(admin, MIN_FEE, 0, _steps());
    }

    function test_initialize_RevertWhen_CooldownExceedsMax() public {
        CustomFeeRegistry registry = _newRegistry();
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        registry.initialize(admin, MIN_FEE, 365 days + 1, _steps());
    }
}

contract CustomFeeRegistryRequestFeeTest is CustomFeeRegistryBaseTest {
    function test_requestFee_Decrease_AppliesImmediately() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeSet(NO_ID, 5_000);
        _requestFee(5_000);

        assertEq(feeRegistry.getFee(NO_ID), 5_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(5_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 1);
        assertEq(metaRegistryMock.lastChangedBoostOperatorId(), NO_ID);
    }

    function test_requestFee_Decrease_ToMinFee() public {
        _requestFee(MIN_FEE);
        assertEq(feeRegistry.getFee(NO_ID), MIN_FEE);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(MIN_FEE));
    }

    function test_requestFee_Decrease_DoesNotNotifyWhenStepValueUnchanged() public {
        _requestFee(7_500);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFee(7_250);

        assertEq(feeRegistry.getFee(NO_ID), 7_250);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_500));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFee_Increase_SetsPending() public {
        _requestFee(5_000);

        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseRequested(NO_ID, 6_000, cooldownUntil);
        _requestFee(6_000);

        // The fee itself is unchanged, but the weight already follows the pending increase.
        assertEq(feeRegistry.getFee(NO_ID), 5_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 2);
    }

    function test_requestFee_Increase_OverwritesPendingAndRestartsCooldown() public {
        _requestFee(5_000);
        _requestFee(6_000);

        vm.warp(block.timestamp + 1 days);
        uint256 cooldownUntil = block.timestamp + COOLDOWN;
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseRequested(NO_ID, 7_000, cooldownUntil);
        _requestFee(7_000);

        assertEq(feeRegistry.getFee(NO_ID), 5_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_000));

        // The old deadline is void: the increase applies only at the restarted one.
        vm.warp(cooldownUntil - 1 days);
        vm.expectRevert(ICustomFeeRegistry.FeeIncreaseCooldownNotElapsed.selector);
        _applyFeeIncrease();

        vm.warp(cooldownUntil);
        _applyFeeIncrease();
        assertEq(feeRegistry.getFee(NO_ID), 7_000);
    }

    function test_requestFee_Increase_DoesNotNotifyWhenFeeBandUnchanged() public {
        _requestFee(4_750);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFee(5_000);

        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 5_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(4_750));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFee_Increase_OverwriteDoesNotNotifyWhenFeeBandUnchanged() public {
        _requestFee(5_000);
        _requestFee(6_000);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _requestFee(6_250);

        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 6_250);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_requestFee_Increase_LoweringPendingRaisesWeight() public {
        _requestFee(5_000);
        _requestFee(7_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_000));

        _requestFee(6_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_000));
        assertEq(feeRegistry.getFee(NO_ID), 5_000);
    }

    function test_requestFee_Decrease_CancelsPending() public {
        _requestFee(5_000);
        _requestFee(6_000);

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseCancelled(NO_ID);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeSet(NO_ID, 4_000);
        _requestFee(4_000);

        assertEq(feeRegistry.getFee(NO_ID), 4_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(4_000));

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.expectRevert(ICustomFeeRegistry.NoFeeIncreaseCooldown.selector);
        _applyFeeIncrease();
    }

    function test_requestFee_RevertWhen_NotOwner() public {
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.requestFee(NO_ID, 5_000);
    }

    function test_requestFee_RevertWhen_BelowMinFee() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _requestFee(MIN_FEE - STEP);
    }

    function test_requestFee_RevertWhen_AboveMaxFee() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _requestFee(MAX_FEE + STEP);
    }

    function test_requestFee_RevertWhen_NotStepAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _requestFee(5_000 + 1);
    }

    function test_requestFee_RevertWhen_BelowTypeMinimum() public {
        _setFeeModifier(0, 2_500, true);
        // The negative modifier raises the operator's minimum to 5_000.
        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _requestFee(4_750);
    }

    function test_requestFee_RevertWhen_SameFee_Unset() public {
        vm.expectRevert(ICustomFeeRegistry.SameFee.selector);
        _requestFee(MAX_FEE);
    }

    function test_requestFee_RevertWhen_SameFee_Set() public {
        _requestFee(5_000);
        vm.expectRevert(ICustomFeeRegistry.SameFee.selector);
        _requestFee(5_000);
    }

    function test_requestFee_RevertWhen_SameFeeWithPendingIncrease() public {
        _requestFee(5_000);
        _requestFee(6_000);

        vm.expectRevert(ICustomFeeRegistry.SameFee.selector);
        _requestFee(5_000);
    }
}

contract CustomFeeRegistryCancelFeeIncreaseTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();
        _requestFee(5_000);
        _requestFee(6_000);
    }

    function test_cancelFeeIncrease() public {
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseCancelled(NO_ID);
        _cancelFeeIncrease();

        assertEq(feeRegistry.getFee(NO_ID), 5_000);
        _assertNoPendingFeeIncrease();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(5_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_cancelFeeIncrease_AfterCooldown() public {
        vm.warp(block.timestamp + COOLDOWN + 1);
        _cancelFeeIncrease();
        _assertNoPendingFeeIncrease();
    }

    function test_cancelFeeIncrease_DoesNotNotifyWhenFeeBandUnchanged() public {
        _cancelFeeIncrease();
        _requestFee(4_750);
        _requestFee(5_000);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _cancelFeeIncrease();

        assertEq(feeRegistry.getFee(NO_ID), 4_750);
        _assertNoPendingFeeIncrease();
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_cancelFeeIncrease_WhenCurrentFeeBelowNewMin() public {
        _setFeeModifier(0, 4_000, true); // New minimum is 6_500.
        _cancelFeeIncrease();

        _assertNoPendingFeeIncrease();
        assertEq(feeRegistry.getFee(NO_ID), 5_000);
    }

    function test_cancelFeeIncrease_RevertWhen_NotOwner() public {
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.cancelFeeIncrease(NO_ID);
    }

    function test_cancelFeeIncrease_RevertWhen_NoPendingIncrease() public {
        _cancelFeeIncrease();
        vm.expectRevert(ICustomFeeRegistry.NoFeeIncreaseCooldown.selector);
        _cancelFeeIncrease();
    }
}

contract CustomFeeRegistryApplyFeeIncreaseTest is CustomFeeRegistryBaseTest {
    uint256 internal cooldownUntil;

    function setUp() public override {
        super.setUp();
        _requestFee(5_000);
        _requestFee(6_000);
        cooldownUntil = block.timestamp + COOLDOWN;
    }

    function test_applyFeeIncrease() public {
        vm.warp(cooldownUntil + 1);

        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseApplied(NO_ID, 6_000);
        _applyFeeIncrease();

        assertEq(feeRegistry.getFee(NO_ID), 6_000);
        // The weight followed the pending fee already, so no new notification.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_applyFeeIncrease_AtExactDeadline() public {
        vm.warp(cooldownUntil);
        _applyFeeIncrease();
        assertEq(feeRegistry.getFee(NO_ID), 6_000);
    }

    function test_applyFeeIncrease_CooldownChangeDoesNotAffectPending() public {
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(COOLDOWN * 2);

        vm.warp(cooldownUntil);
        _applyFeeIncrease();
        assertEq(feeRegistry.getFee(NO_ID), 6_000);
    }

    function test_applyFeeIncrease_RevertWhen_NotOwner() public {
        vm.warp(cooldownUntil + 1);
        vm.expectRevert(IStepwiseWeightBoost.SenderIsNotNodeOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.applyFeeIncrease(NO_ID);
    }

    function test_applyFeeIncrease_RevertWhen_NotElapsed() public {
        vm.warp(cooldownUntil - 1);
        vm.expectRevert(ICustomFeeRegistry.FeeIncreaseCooldownNotElapsed.selector);
        _applyFeeIncrease();
    }

    function test_applyFeeIncrease_RevertWhen_NoPending() public {
        vm.warp(cooldownUntil + 1);
        _applyFeeIncrease();

        vm.expectRevert(ICustomFeeRegistry.NoFeeIncreaseCooldown.selector);
        _applyFeeIncrease();
    }

    function test_applyFeeIncrease_RevertWhen_PendingFeeBelowCurrentMin() public {
        _setFeeModifier(0, 4_000, true); // New minimum is 6_500, pending fee is 6_000.
        vm.warp(cooldownUntil);

        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _applyFeeIncrease();

        assertEq(feeRegistry.getFee(NO_ID), 5_000);
        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 6_000);
        assertEq(feeRegistry.getFeeIncreaseCooldownUntil(NO_ID), cooldownUntil);
    }

    function test_applyFeeIncrease_InvalidPendingCanBeNormalizedPermissionlessly() public {
        _setFeeModifier(0, 4_000, true); // New minimum is 6_500, pending fee is 6_000.
        vm.warp(cooldownUntil);

        vm.expectRevert(ICustomFeeRegistry.InvalidFee.selector);
        _applyFeeIncrease();

        vm.prank(stranger);
        feeRegistry.normalizeFees(UintArr(NO_ID));

        assertEq(feeRegistry.getFee(NO_ID), 6_500);
        _assertNoPendingFeeIncrease();
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_500));
    }
}

contract CustomFeeRegistryNormalizeFeesTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();

        // Operator 0 is left below the new minimum; the other operators remain unset and valid.
        _setFeeModifier(0, 2_500, true);
        _requestFee(5_000);
        _setFeeModifier(0, 5_000, true);
    }

    function test_normalizeFees() public {
        uint256 normalizedCount = feeRegistry.normalizeFees(UintArr(0, 1, 2));

        assertEq(normalizedCount, 1);
        assertEq(feeRegistry.getFee(0), 7_500);
        assertEq(feeRegistry.getFee(1), MAX_FEE);
        assertEq(feeRegistry.getFee(2), MAX_FEE);
    }

    function test_normalizeFees_SetsFeeToMinimumAndRestoresEffectiveFee() public {
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 0); // max(0, 5_000 - 5_000)

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeSet(NO_ID, 7_500);
        vm.prank(stranger); // permissionless
        feeRegistry.normalizeFees(UintArr(NO_ID));

        assertEq(feeRegistry.getFee(NO_ID), 7_500);
        // The effective fee is back at the default minimum.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MIN_FEE);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_500));
    }

    function test_normalizeFees_CancelsPendingIncrease() public {
        _requestFee(8_000);

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseCancelled(NO_ID);
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeSet(NO_ID, 7_500);
        vm.prank(stranger);
        feeRegistry.normalizeFees(UintArr(NO_ID));

        assertEq(feeRegistry.getFee(NO_ID), 7_500);
        _assertNoPendingFeeIncrease();
    }

    function test_normalizeFees_CancelsExpiredPendingIncrease() public {
        _requestFee(8_000);
        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(stranger);
        feeRegistry.normalizeFees(UintArr(NO_ID));

        assertEq(feeRegistry.getFee(NO_ID), 7_500);
        _assertNoPendingFeeIncrease();
    }

    function test_normalizeFees_DoesNotNotifyWhenPendingFeeEqualsMin() public {
        _requestFee(7_500);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(stranger);
        feeRegistry.normalizeFees(UintArr(NO_ID));

        assertEq(feeRegistry.getFee(NO_ID), 7_500);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_normalizeFees_SkipsDuplicatesAndValidOperators() public {
        uint256[] memory nodeOperatorIds = new uint256[](4);
        nodeOperatorIds[0] = 0;
        nodeOperatorIds[1] = 0;
        nodeOperatorIds[2] = 2;
        nodeOperatorIds[3] = 1;
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        uint256 normalizedCount = feeRegistry.normalizeFees(nodeOperatorIds);

        assertEq(normalizedCount, 1);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore + 1);
    }

    function test_normalizeFees_EmptyArray() public {
        uint256 normalizedCount = feeRegistry.normalizeFees(UintArr());
        assertEq(normalizedCount, 0);
    }

    function test_normalizeFees_NoFeesToNormalize() public {
        uint256[] memory nodeOperatorIds = UintArr(0, 1);
        feeRegistry.normalizeFees(nodeOperatorIds);

        uint256 normalizedCount = feeRegistry.normalizeFees(nodeOperatorIds);

        assertEq(normalizedCount, 0);
    }
}

contract CustomFeeRegistrySetDefaultMinFeeTest is CustomFeeRegistryBaseTest {
    function test_setDefaultMinFee() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.DefaultMinFeeSet(2_000);
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(2_000);

        assertEq(feeRegistry.getDefaultMinFee(), 2_000);
    }

    function test_setDefaultMinFee_UsesLastWeightStepBelowLastThreshold() public {
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(1_000);

        _requestFee(1_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_000));
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 25_000);
    }

    function test_setDefaultMinFee_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setDefaultMinFee(2_000);
    }

    function test_setDefaultMinFee_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(0);
    }

    function test_setDefaultMinFee_RevertWhen_NotBelowCurrent() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(MIN_FEE);
    }

    function test_setDefaultMinFee_RevertWhen_NotStepAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(2_000 + 1);
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
        // The modifier tops the effective fee up to 100% for an unset operator.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_BP);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);
    }

    function test_setFeeModifier_Negative() public {
        _setFeeModifier(0, 2_500, true);

        FeeModifier memory feeModifier = feeRegistry.getFeeModifier(0);
        assertEq(feeModifier.value, 2_500);
        assertTrue(feeModifier.negative);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE + 2_500);
    }

    function test_setFeeModifier_ZeroWithAnySign() public {
        _setFeeModifier(0, 0, true);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_FEE);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);

        _setFeeModifier(0, 0, false);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_FEE);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);
    }

    function test_setFeeModifier_DoesNotNotifyAndDoesNotMoveWeight() public {
        _requestFee(5_000);
        uint256 weightBefore = feeRegistry.getWeightBoostMultiplierBP(NO_ID);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _setFeeModifier(0, 1_250, false);

        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), weightBefore);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_setFeeModifier_SameFeeSameWeightAcrossTypes() public {
        _setFeeModifier(0, 1_250, false);
        _accounting.setBondCurve(1, 1); // Add curve 1 without moving NO_ID from curve 0.
        _setFeeModifier(1, 2_500, true);
        _requestFee(5_000);

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
        // MAX_BP - DEFAULT_MAX_FEE = 1_250 is the largest positive modifier.
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeModifier.selector);
        _setFeeModifier(0, 1_250 + STEP, false);
    }

    function test_setFeeModifier_RevertWhen_NegativeAboveMax() public {
        // DEFAULT_MAX_FEE - defaultMinFee = 6_250 is the largest negative modifier.
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeModifier.selector);
        _setFeeModifier(0, 6_250 + STEP, true);
    }

    function test_setFeeModifier_RevertWhen_NotStepAligned() public {
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
            // Fee discounts are FEE_STEP-aligned and stay below DEFAULT_MAX_FEE.
            steps[i] = Step({ threshold: uint128(i * STEP), value: uint128((i + 1) * 100) });
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

    function test_setSteps_ChangesFeeWeights() public {
        _requestFee(5_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 20_000);

        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: 3_750, value: 7_000 });
        _setSteps(steps);

        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 17_000);
    }

    function test_setSteps_AllowsMaximumValues() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(MAX_FEE - STEP), value: uint128(feeRegistry.MAX_STEP_VALUE()) });
        _setSteps(steps);

        assertEq(feeRegistry.getSteps()[0].threshold, MAX_FEE - STEP);
    }

    function test_setSteps_RevertWhen_FeeDiscountAtMaxFee() public {
        Step[] memory steps = new Step[](1);
        steps[0] = Step({ threshold: uint128(MAX_FEE), value: 1 });
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

contract CustomFeeRegistrySetFeeIncreaseCooldownTest is CustomFeeRegistryBaseTest {
    function test_setFeeIncreaseCooldown() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeIncreaseCooldownSet(30 days);
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(30 days);

        assertEq(feeRegistry.getFeeIncreaseCooldown(), 30 days);
    }

    function test_setFeeIncreaseCooldown_RevertWhen_NotAdmin() public {
        expectRoleRevert(stranger, feeRegistry.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeRegistry.setFeeIncreaseCooldown(30 days);
    }

    function test_setFeeIncreaseCooldown_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(0);
    }

    function test_setFeeIncreaseCooldown_Max() public {
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(365 days);

        _requestFee(5_000);
        _requestFee(6_000);

        assertEq(feeRegistry.getFeeIncreaseCooldown(), 365 days);
        assertEq(feeRegistry.getFeeIncreaseCooldownUntil(NO_ID), block.timestamp + 365 days);
    }

    function test_setFeeIncreaseCooldown_RevertWhen_ExceedsMax() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(365 days + 1);
    }
}

contract CustomFeeRegistryViewsTest is CustomFeeRegistryBaseTest {
    function test_getFee_UnsetReadsAsDefaultMax() public view {
        assertEq(feeRegistry.getFee(NO_ID), MAX_FEE);
    }

    function test_getPendingFeeIncreaseAndCooldownUntil() public {
        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 0);
        assertEq(feeRegistry.getFeeIncreaseCooldownUntil(NO_ID), 0);

        _requestFee(5_000);
        _requestFee(6_000);

        assertEq(feeRegistry.getPendingFeeIncrease(NO_ID), 6_000);
        assertEq(feeRegistry.getFeeIncreaseCooldownUntil(NO_ID), block.timestamp + COOLDOWN);
    }

    function test_getWeightBoostMultiplierBP_UnsetIsOne() public view {
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_StepsAndBands() public {
        _requestFee(MAX_FEE - STEP);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);

        _requestFee(7_500);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 12_000);

        _requestFee(7_250);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 12_000);

        _requestFee(MIN_FEE);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 25_000);
    }

    function test_getWeightBoostMultiplierBP_BinarySearchAtMaxSteps() public {
        uint256 stepsCount = feeRegistry.MAX_STEPS();
        Step[] memory steps = new Step[](stepsCount);
        for (uint256 i; i < stepsCount; ++i) {
            steps[i] = Step({ threshold: uint128(i * STEP), value: uint128(i * 1_000) });
        }
        vm.prank(admin);
        feeRegistry.setSteps(steps);

        _requestFee(4_500); // Discount 4_250 reaches step 17.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 17_000);

        vm.prank(admin);
        feeRegistry.setDefaultMinFee(STEP);
        _requestFee(STEP); // Discount 8_500 reaches the final step 34.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + 34_000);
    }

    function test_getEffectiveFee_NoModifier() public {
        _requestFee(5_000);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 5_000);
    }

    function test_getEffectiveFee_ClampsAtZero() public {
        _setFeeModifier(0, 2_500, true);
        _requestFee(5_000);
        _setFeeModifier(0, 5_500, true);

        assertEq(feeRegistry.getEffectiveFee(NO_ID), 0);
    }

    function test_getEffectiveFee_PendingIncreaseIsExcluded() public {
        _requestFee(5_000);
        _requestFee(6_000);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 5_000);
    }

    function test_getMinFee_Default() public view {
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);
    }
}
