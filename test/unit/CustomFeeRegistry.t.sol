// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CustomFeeRegistry } from "src/CustomFeeRegistry.sol";
import { ICustomFeeRegistry, TypeBonus } from "src/interfaces/ICustomFeeRegistry.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { MetaRegistryMock } from "../helpers/mocks/MetaRegistryMock.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract CustomFeeRegistryBaseTest is Test, Utilities, Fixtures {
    CuratedMock public module;
    CustomFeeRegistry public feeRegistry;
    MetaRegistryMock public metaRegistryMock;
    AccountingMock internal acct;

    address public admin;
    address public nodeOperatorOwner;
    address public stranger;

    uint256 internal constant MAX_BP = 10_000;
    uint256 internal constant STEP = 250;
    uint256 internal constant MAX_FEE = 8_750;
    uint256 internal constant SLOPE = 400;
    uint256 internal constant MIN_FEE = 2_500;
    uint256 internal constant COOLDOWN = 15 days;

    uint256 internal constant NO_ID = 0;

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

        feeRegistry = new CustomFeeRegistry(address(module));
        _enableInitializers(address(feeRegistry));
        feeRegistry.initialize(admin, MIN_FEE, COOLDOWN);

        acct = AccountingMock(address(module.ACCOUNTING()));
    }

    function _weight(uint256 fee) internal pure returns (uint256) {
        return MAX_BP + ((MAX_FEE - fee) / STEP) * SLOPE;
    }

    function _requestFee(uint256 fee) internal {
        vm.prank(nodeOperatorOwner);
        feeRegistry.requestFee(NO_ID, fee);
    }

    function _setTypeBonus(uint256 curveId, uint256 value, bool negative) internal {
        vm.prank(admin);
        feeRegistry.setTypeBonus(curveId, value, negative);
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
        assertEq(feeRegistry.WEIGHT_BOOST_PER_STEP(), SLOPE);
    }
}

contract CustomFeeRegistryInitializeTest is CustomFeeRegistryBaseTest {
    function test_initialize() public view {
        assertTrue(feeRegistry.hasRole(feeRegistry.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(feeRegistry.getDefaultMinFee(), MIN_FEE);
        assertEq(feeRegistry.getFeeIncreaseCooldown(), COOLDOWN);
    }

    function test_initialize_EmitsEvents() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectEmit(address(tp));
        emit ICustomFeeRegistry.DefaultMinFeeSet(MIN_FEE);
        vm.expectEmit(address(tp));
        emit ICustomFeeRegistry.FeeIncreaseCooldownSet(COOLDOWN);
        tp.initialize(admin, MIN_FEE, COOLDOWN);
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(ICustomFeeRegistry.ZeroAdminAddress.selector);
        tp.initialize(address(0), MIN_FEE, COOLDOWN);
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeRegistry.initialize(admin, MIN_FEE, COOLDOWN);
    }

    function test_initialize_RevertWhen_ZeroMinFee() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        tp.initialize(admin, 0, COOLDOWN);
    }

    function test_initialize_RevertWhen_MinFeeAtOrAboveMax() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        tp.initialize(admin, MAX_FEE, COOLDOWN);
    }

    function test_initialize_RevertWhen_MinFeeNotStepAligned() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(ICustomFeeRegistry.InvalidDefaultMinFee.selector);
        tp.initialize(admin, MIN_FEE + 1, COOLDOWN);
    }

    function test_initialize_RevertWhen_ZeroCooldown() public {
        CustomFeeRegistry tp = new CustomFeeRegistry(address(module));
        _enableInitializers(address(tp));
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        tp.initialize(admin, MIN_FEE, 0);
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
        // Exactly 2x at the planned minimum.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 2 * MAX_BP);
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
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);

        vm.warp(cooldownUntil);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
        assertEq(feeRegistry.getFee(NO_ID), 7_000);
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
        emit ICustomFeeRegistry.FeeSet(NO_ID, 4_000);
        _requestFee(4_000);

        assertEq(feeRegistry.getFee(NO_ID), 4_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(4_000));

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.expectRevert(ICustomFeeRegistry.NoFeeIncreaseCooldown.selector);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
    }

    function test_requestFee_RevertWhen_NotOwner() public {
        vm.expectRevert(ICustomFeeRegistry.SenderIsNotOperatorOwner.selector);
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
        _setTypeBonus(0, 2_500, true);
        // The negative bonus raises the operator's minimum to 5_000.
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

    function test_requestFee_RevertWhen_SameFeeWithPending() public {
        _requestFee(5_000);
        _requestFee(6_000);
        // Cancelling to the very same fee is not a thing: only a decrease cancels.
        vm.expectRevert(ICustomFeeRegistry.SameFee.selector);
        _requestFee(5_000);
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
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);

        assertEq(feeRegistry.getFee(NO_ID), 6_000);
        // The weight followed the pending fee already, so no new notification.
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(6_000));
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_applyFeeIncrease_AtExactDeadline() public {
        vm.warp(cooldownUntil);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
        assertEq(feeRegistry.getFee(NO_ID), 6_000);
    }

    function test_applyFeeIncrease_CooldownChangeDoesNotAffectPending() public {
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(COOLDOWN * 2);

        vm.warp(cooldownUntil);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
        assertEq(feeRegistry.getFee(NO_ID), 6_000);
    }

    function test_applyFeeIncrease_RevertWhen_NotOwner() public {
        vm.warp(cooldownUntil + 1);
        vm.expectRevert(ICustomFeeRegistry.SenderIsNotOperatorOwner.selector);
        vm.prank(stranger);
        feeRegistry.applyFeeIncrease(NO_ID);
    }

    function test_applyFeeIncrease_RevertWhen_NotElapsed() public {
        vm.warp(cooldownUntil - 1);
        vm.expectRevert(ICustomFeeRegistry.FeeIncreaseCooldownNotElapsed.selector);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
    }

    function test_applyFeeIncrease_RevertWhen_NoPending() public {
        vm.warp(cooldownUntil + 1);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);

        vm.expectRevert(ICustomFeeRegistry.NoFeeIncreaseCooldown.selector);
        vm.prank(nodeOperatorOwner);
        feeRegistry.applyFeeIncrease(NO_ID);
    }
}

contract CustomFeeRegistryRestoreFeeToMinTest is CustomFeeRegistryBaseTest {
    function setUp() public override {
        super.setUp();
        // The operator settles at the type minimum, then the DAO tightens the bonus.
        _setTypeBonus(0, 2_500, true);
        _requestFee(5_000);
        _setTypeBonus(0, 5_000, true);
        // The minimum is now 7_500 and the operator at 5_000 sits below it.
    }

    function test_restoreFeeToMin() public {
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 0); // max(0, 5_000 - 5_000)

        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.FeeSet(NO_ID, 7_500);
        vm.prank(stranger); // permissionless
        feeRegistry.restoreFeeToMin(NO_ID);

        assertEq(feeRegistry.getFee(NO_ID), 7_500);
        // The effective fee is back at the default minimum.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MIN_FEE);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(7_500));
    }

    function test_restoreFeeToMin_RevertWhen_FeeNotBelowMinFee() public {
        vm.prank(stranger);
        feeRegistry.restoreFeeToMin(NO_ID);

        vm.expectRevert(ICustomFeeRegistry.FeeNotBelowMinFee.selector);
        vm.prank(stranger);
        feeRegistry.restoreFeeToMin(NO_ID);
    }

    function test_restoreFeeToMin_RevertWhen_UnsetOperator() public {
        // An unset operator reads as DEFAULT_MAX_FEE and can never be below the minimum.
        vm.expectRevert(ICustomFeeRegistry.FeeNotBelowMinFee.selector);
        vm.prank(stranger);
        feeRegistry.restoreFeeToMin(1);
    }

    function test_restoreFeeToMin_RevertWhen_IncreasePending() public {
        vm.prank(nodeOperatorOwner);
        feeRegistry.requestFee(NO_ID, 8_000);

        vm.expectRevert(ICustomFeeRegistry.FeeIncreaseCooldownActive.selector);
        vm.prank(stranger);
        feeRegistry.restoreFeeToMin(NO_ID);
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

    function test_setDefaultMinFee_OpensWeightsAboveTwo() public {
        vm.prank(admin);
        feeRegistry.setDefaultMinFee(1_000);

        // The weight line does not move: fees below the initial minimum extrapolate above 2x.
        _requestFee(1_000);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), _weight(1_000));
        assertGt(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 2 * MAX_BP);
    }

    function test_setDefaultMinFee_RevertWhen_NotAdmin() public {
        vm.expectRevert();
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

contract CustomFeeRegistrySetTypeBonusTest is CustomFeeRegistryBaseTest {
    function test_setTypeBonus_Positive() public {
        vm.expectEmit(address(feeRegistry));
        emit ICustomFeeRegistry.TypeBonusSet(0, 1_250, false);
        _setTypeBonus(0, 1_250, false);

        TypeBonus memory bonus = feeRegistry.getTypeBonus(0);
        assertEq(bonus.value, 1_250);
        assertFalse(bonus.negative);
        // The bonus tops the effective fee up to 100% for an unset operator.
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_BP);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);
    }

    function test_setTypeBonus_Negative() public {
        _setTypeBonus(0, 2_500, true);

        TypeBonus memory bonus = feeRegistry.getTypeBonus(0);
        assertEq(bonus.value, 2_500);
        assertTrue(bonus.negative);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE + 2_500);
    }

    function test_setTypeBonus_ZeroWithAnySign() public {
        _setTypeBonus(0, 0, true);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_FEE);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);

        _setTypeBonus(0, 0, false);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), MAX_FEE);
        assertEq(feeRegistry.getMinFee(NO_ID), MIN_FEE);
    }

    function test_setTypeBonus_DoesNotNotifyAndDoesNotMoveWeight() public {
        _requestFee(5_000);
        uint256 weightBefore = feeRegistry.getWeightBoostMultiplierBP(NO_ID);
        uint256 notifyCallsBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        _setTypeBonus(0, 1_250, false);

        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), weightBefore);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), notifyCallsBefore);
    }

    function test_setTypeBonus_SameFeeSameWeightAcrossTypes() public {
        _setTypeBonus(0, 1_250, false);
        _setTypeBonus(1, 2_500, true);
        _requestFee(5_000);

        uint256 weightOnTypeA = feeRegistry.getWeightBoostMultiplierBP(NO_ID);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 6_250);

        // Moving the operator to another type shifts only the effective fee, never the weight.
        acct.setBondCurve(NO_ID, 1);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), weightOnTypeA);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 2_500);
    }

    function test_setTypeBonus_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(stranger);
        feeRegistry.setTypeBonus(0, 1_250, false);
    }

    function test_setTypeBonus_RevertWhen_PositiveAboveMax() public {
        // MAX_BP - DEFAULT_MAX_FEE = 1_250 is the largest positive bonus.
        vm.expectRevert(ICustomFeeRegistry.InvalidTypeBonus.selector);
        _setTypeBonus(0, 1_250 + STEP, false);
    }

    function test_setTypeBonus_RevertWhen_NegativeAboveMax() public {
        // DEFAULT_MAX_FEE - defaultMinFee = 6_250 is the largest negative bonus.
        vm.expectRevert(ICustomFeeRegistry.InvalidTypeBonus.selector);
        _setTypeBonus(0, 6_250 + STEP, true);
    }

    function test_setTypeBonus_RevertWhen_NotStepAligned() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidTypeBonus.selector);
        _setTypeBonus(0, 100, false);
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
        vm.expectRevert();
        vm.prank(stranger);
        feeRegistry.setFeeIncreaseCooldown(30 days);
    }

    function test_setFeeIncreaseCooldown_RevertWhen_Zero() public {
        vm.expectRevert(ICustomFeeRegistry.InvalidFeeIncreaseCooldown.selector);
        vm.prank(admin);
        feeRegistry.setFeeIncreaseCooldown(0);
    }
}

contract CustomFeeRegistryViewsTest is CustomFeeRegistryBaseTest {
    function test_getFee_UnsetReadsAsDefaultMax() public view {
        assertEq(feeRegistry.getFee(NO_ID), MAX_FEE);
    }

    function test_getWeightBoostMultiplierBP_UnsetIsOne() public view {
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP);
    }

    function test_getWeightBoostMultiplierBP_Linearity() public {
        _requestFee(MAX_FEE - STEP);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), MAX_BP + SLOPE);

        _requestFee(MIN_FEE);
        assertEq(feeRegistry.getWeightBoostMultiplierBP(NO_ID), 2 * MAX_BP);
    }

    function test_getEffectiveFee_NoBonus() public {
        _requestFee(5_000);
        assertEq(feeRegistry.getEffectiveFee(NO_ID), 5_000);
    }

    function test_getEffectiveFee_ClampsAtZero() public {
        _setTypeBonus(0, 2_500, true);
        _requestFee(5_000);
        _setTypeBonus(0, 5_500, true);

        // max(0, 5_000 - 5_500)
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
