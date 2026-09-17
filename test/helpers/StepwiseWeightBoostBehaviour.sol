// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IStepwiseWeightBoost, Step } from "src/interfaces/IStepwiseWeightBoost.sol";

import { Utilities } from "./Utilities.sol";

/// @dev `DEFAULT_ADMIN_ROLE` is a constant of the AccessControl implementation rather than a member of
///      its interface, so the behaviour reads it through this minimal view.
interface IStepwiseAdminRole {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}

/// @notice Behaviour shared by every StepwiseWeightBoost provider. A suite mixes this in and supplies the
///         provider, its admin, and a domain-valid step function; the checks below then cover the
///         capability itself so provider suites only assert their own domain rules.
abstract contract StepwiseWeightBoostBehaviour is Test, Utilities {
    /// @dev Provider under test, already initialized.
    function _stepwise() internal view virtual returns (IStepwiseWeightBoost);

    /// @dev Holder of DEFAULT_ADMIN_ROLE on the provider.
    function _stepwiseAdmin() internal view virtual returns (address);

    /// @dev `count` domain-valid steps with strictly ascending thresholds and values.
    function _stepwiseSteps(uint256 count) internal view virtual returns (Step[] memory);

    function test_setSteps_StoresStepsInOrder() public {
        Step[] memory steps = _stepwiseSteps(3);

        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);

        Step[] memory stored = _stepwise().getSteps();
        assertEq(stored.length, steps.length);
        for (uint256 i; i < steps.length; ++i) {
            assertEq(stored[i].threshold, steps[i].threshold);
            assertEq(stored[i].value, steps[i].value);
        }
    }

    function test_setSteps_ReplacesPreviousSteps() public {
        vm.startPrank(_stepwiseAdmin());
        _stepwise().setSteps(_stepwiseSteps(3));
        _stepwise().setSteps(_stepwiseSteps(1));
        vm.stopPrank();

        assertEq(_stepwise().getSteps().length, 1);
    }

    function test_setSteps_EmitsStepsSet() public {
        Step[] memory steps = _stepwiseSteps(2);

        vm.expectEmit(address(_stepwise()));
        emit IStepwiseWeightBoost.StepsSet(steps);
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);
    }

    function test_setSteps_AllowsMaxSteps() public {
        Step[] memory steps = _stepwiseSteps(_stepwise().MAX_STEPS());

        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);

        assertEq(_stepwise().getSteps().length, steps.length);
    }

    function test_setSteps_RevertWhen_NotAdmin() public {
        address stranger = makeAddr("stepwiseStranger");
        Step[] memory steps = _stepwiseSteps(1);

        expectRoleRevert(stranger, IStepwiseAdminRole(address(_stepwise())).DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        _stepwise().setSteps(steps);
    }

    function test_setSteps_RevertWhen_Empty() public {
        vm.expectRevert(IStepwiseWeightBoost.InvalidStepCount.selector);
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(new Step[](0));
    }

    function test_setSteps_RevertWhen_AboveMaxSteps() public {
        // The count guard runs before per-step validation, so the payload needs no domain-valid values.
        Step[] memory steps = new Step[](_stepwise().MAX_STEPS() + 1);

        vm.expectRevert(IStepwiseWeightBoost.InvalidStepCount.selector);
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);
    }

    function test_setSteps_RevertWhen_ThresholdsNotAscending() public {
        Step[] memory steps = _stepwiseSteps(2);
        steps[1].threshold = steps[0].threshold;

        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.UnorderedSteps.selector, 1));
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);
    }

    function test_setSteps_RevertWhen_ValuesNotAscending() public {
        Step[] memory steps = _stepwiseSteps(2);
        steps[1].value = steps[0].value;

        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.UnorderedSteps.selector, 1));
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);
    }

    function test_setSteps_RevertWhen_ValueAboveMaxStepValue() public {
        Step[] memory steps = _stepwiseSteps(1);
        steps[0].value = uint128(_stepwise().MAX_STEP_VALUE() + 1);

        vm.expectRevert(abi.encodeWithSelector(IStepwiseWeightBoost.InvalidStep.selector, 0));
        vm.prank(_stepwiseAdmin());
        _stepwise().setSteps(steps);
    }

    function test_getInitializedVersion() public view {
        assertEq(_stepwise().getInitializedVersion(), 1);
    }
}
