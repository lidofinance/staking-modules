// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Test.sol";

import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleObtainDepositData is ModuleFixtures {
    function test_obtainDepositData() public assertInvariants {
        uint256 nodeOperatorId = createNodeOperator(1);
        (bytes memory keys, bytes memory signatures) = module.getSigningKeysWithSignatures(nodeOperatorId, 0, 1);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(nodeOperatorId, 0);
        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module.obtainDepositData(1, "");
        assertEq(obtainedKeys, keys);
        assertEq(obtainedSignatures, signatures);
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(nodeOperatorId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_obtainDepositData_counters() public assertInvariants {
        uint256 keysCount = 1;
        uint256 noId = createNodeOperator(keysCount);
        (bytes memory keys, bytes memory signatures) = module.getSigningKeysWithSignatures(noId, 0, keysCount);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositedSigningKeysCountChanged(noId, keysCount);
        (bytes memory depositedKeys, bytes memory depositedSignatures) = module.obtainDepositData(keysCount, "");

        assertEq(keys, depositedKeys);
        assertEq(signatures, depositedSignatures);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalDepositedKeys, 1);
        assertEq(no.depositableValidatorsCount, 0);
        assertEq(module.getTotalModuleStake(), keysCount * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), keysCount * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_obtainDepositData_zeroDeposits() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonceBefore = module.getNonce();

        (bytes memory publicKeys, bytes memory signatures) = module.obtainDepositData(0, "");

        assertEq(publicKeys.length, 0);
        assertEq(signatures.length, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalDepositedKeys, 0);
        assertEq(no.depositableValidatorsCount, 1);
        assertEq(module.getNonce(), nonceBefore);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_obtainDepositData_unvettedKeys() public assertInvariants {
        createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(1);
        createNodeOperator(3);

        unvetKeys(secondNoId, 0);

        module.obtainDepositData(5, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 5);
        assertEq(depositableValidatorsCount, 0);
        assertEq(module.getTotalModuleStake(), 5 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_obtainDepositData_counters_WhenLessThanLastBatch() public assertInvariants {
        uint256 noId = createNodeOperator(7);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositedSigningKeysCountChanged(noId, 3);
        module.obtainDepositData(3, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalDepositedKeys, 3);
        assertEq(no.depositableValidatorsCount, 4);
        assertEq(module.getTotalModuleStake(), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_obtainDepositData_nonceChanged() public assertInvariants {
        createNodeOperator();
        uint256 nonce = module.getNonce();

        module.obtainDepositData(1, "");
        assertEq(module.getNonce(), nonce + 1);
    }

    function testFuzz_obtainDepositData_MultipleOperators(uint256 batchCount, uint256 random) public assertInvariants {
        batchCount = bound(batchCount, 1, 20);
        random = bound(random, 1, 20);
        vm.assume(batchCount > random);

        uint256 totalKeys;
        for (uint256 i = 1; i < batchCount + 1; ++i) {
            uint256 keys = i / random + 1;
            createNodeOperator(keys);
            totalKeys += keys;
        }

        module.obtainDepositData(totalKeys - random, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertLe(totalDepositedValidators, totalKeys - random);
        assertEq(totalDepositedValidators + depositableValidatorsCount, totalKeys);
    }

    function testFuzz_obtainDepositData_OneOperator(uint256 batchCount, uint256 random) public assertInvariants {
        batchCount = bound(batchCount, 1, 20);
        random = bound(random, 1, 20);
        vm.assume(batchCount > random);

        uint256 totalKeys = 1;
        createNodeOperator(1);
        for (uint256 i = 1; i < batchCount + 1; ++i) {
            uint256 keys = i / random + 1;
            uploadMoreKeys(0, keys);
            totalKeys += keys;
        }

        module.obtainDepositData(totalKeys - random, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalDepositedKeys, totalKeys - random);
        assertEq(no.depositableValidatorsCount, random);
    }

    function test_stakingRouterRole_obtainDepositData() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.obtainDepositData(0, "");
    }

    function test_stakingRouterRole_obtainDepositData_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.obtainDepositData(0, "");
    }
}

abstract contract ModuleUpdateTargetValidatorsLimits is ModuleFixtures {
    function test_updateTargetValidatorsLimits() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_updateTargetValidatorsLimits_sameValues() public assertInvariants {
        uint256 noId = createNodeOperator();

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1);
        assertEq(summary.targetValidatorsCount, 1);
    }

    function test_updateTargetValidatorsLimits_limitIsZero() public assertInvariants {
        uint256 noId = createNodeOperator();
        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 0);
        module.updateTargetValidatorsLimits(noId, 1, 0);
    }

    function test_updateTargetValidatorsLimits_FromDisabledToDisabled_withNonZeroTargetLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.targetLimit, 0);
    }

    function test_updateTargetValidatorsLimits_enableSoftLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 10);
        module.updateTargetValidatorsLimits(noId, 1, 10);
    }

    function test_updateTargetValidatorsLimits_enableHardLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 2, 10);
        module.updateTargetValidatorsLimits(noId, 2, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withNonZeroTargetLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withZeroTargetLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withNonZeroTargetLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withZeroTargetLimit() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_switchFromHardToSoftLimit() public {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 5);
        module.updateTargetValidatorsLimits(noId, 1, 5);
    }

    function test_updateTargetValidatorsLimits_switchFromSoftToHardLimit() public {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 2, 5);
        module.updateTargetValidatorsLimits(noId, 2, 5);
    }

    function test_updateTargetValidatorsLimits_NoUnvetKeysWhenLimitDisabled() public {
        uint256 noId = createNodeOperator(2);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 0, 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 2);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_NoNodeOperator() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.updateTargetValidatorsLimits(0, 1, 1);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitExceedsUint32() public {
        createNodeOperator(1);
        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(0, 1, uint256(type(uint32).max) + 1);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitModeExceedsMax() public {
        createNodeOperator(1);
        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(0, 3, 1);
    }
}

abstract contract ModuleUpdateExitedValidatorsCount is ModuleFixtures {
    function test_updateExitedValidatorsCount_NonZero() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 1);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 1, "totalExitedKeys not increased");

        assertEq(module.getNonce(), nonce);
    }

    function test_updateExitedValidatorsCount_MultipleOperators() public assertInvariants {
        uint256 firstNodeOperator = createNodeOperator(1);
        uint256 secondNodeOperator = createNodeOperator(3);
        module.obtainDepositData(4, "");
        uint256 nonce = module.getNonce();
        (uint256 totalExitedValidators, , ) = module.getStakingModuleSummary();
        assertEq(totalExitedValidators, 0);

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(firstNodeOperator, 1);
        emit IBaseModule.ExitedSigningKeysCountChanged(secondNodeOperator, 2);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000), bytes8(0x0000000000000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001), bytes16(0x00000000000000000000000000000002))
        );

        NodeOperator memory firstNo = module.getNodeOperator(firstNodeOperator);
        NodeOperator memory secondNo = module.getNodeOperator(secondNodeOperator);
        assertEq(firstNo.totalExitedKeys, 1, "totalExitedKeys not increased for first operator");
        assertEq(secondNo.totalExitedKeys, 2, "totalExitedKeys not increased for second operator");
        (totalExitedValidators, , ) = module.getStakingModuleSummary();
        assertEq(totalExitedValidators, 3, "totalExitedValidators not increased");

        assertEq(module.getNonce(), nonce);
    }

    function test_updateExitedValidatorsCount_revertWhen_exitedGreaterThanDeposited() public assertInvariants {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000002))
        );
    }

    function test_updateExitedValidatorsCount_revertWhen_exitedDecreases() public assertInvariants {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000000))
        );
    }
}

abstract contract ModuleUnsafeUpdateValidatorsCount is ModuleFixtures {
    function test_unsafeUpdateValidatorsCount() public assertInvariants {
        uint256 noId = createNodeOperator(5);
        module.obtainDepositData(5, "");

        NodeOperator memory noBefore = module.getNodeOperator(noId);
        assertEq(noBefore.totalExitedKeys, 0);
        assertEq(noBefore.totalDepositedKeys, 5);
        assertEq(noBefore.stuckValidatorsCount, 0);
        assertEq(noBefore.depositableValidatorsCount, 0);
        StakingModuleSummary memory summaryBefore = getStakingModuleSummary();
        assertEq(summaryBefore.totalExitedValidators, 0);
        assertEq(summaryBefore.totalDepositedValidators, 5);
        assertEq(summaryBefore.depositableValidatorsCount, 0);

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 5);
        module.unsafeUpdateValidatorsCount(noId, 5);

        NodeOperator memory noAfter = module.getNodeOperator(noId);
        assertEq(noAfter.totalExitedKeys, 5);
        assertEq(noAfter.totalDepositedKeys, 5);
        assertEq(noAfter.stuckValidatorsCount, 0);
        assertEq(noAfter.depositableValidatorsCount, 0);
        StakingModuleSummary memory summaryAfter = getStakingModuleSummary();
        assertEq(summaryAfter.totalExitedValidators, 5);
        assertEq(summaryAfter.totalDepositedValidators, 5);
        assertEq(summaryAfter.depositableValidatorsCount, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_unsafeUpdateValidatorsCount_allowsDecrease() public assertInvariants {
        uint256 noId = createNodeOperator(5);
        module.obtainDepositData(5, "");

        NodeOperator memory noBefore = module.getNodeOperator(noId);
        assertEq(noBefore.totalExitedKeys, 0);
        assertEq(noBefore.totalDepositedKeys, 5);
        assertEq(noBefore.stuckValidatorsCount, 0);
        assertEq(noBefore.depositableValidatorsCount, 0);
        StakingModuleSummary memory summaryBefore = getStakingModuleSummary();
        assertEq(summaryBefore.totalExitedValidators, 0);
        assertEq(summaryBefore.totalDepositedValidators, 5);
        assertEq(summaryBefore.depositableValidatorsCount, 0);

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 5);
        module.unsafeUpdateValidatorsCount(noId, 5);

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 3);
        module.unsafeUpdateValidatorsCount(noId, 3);

        NodeOperator memory noAfter = module.getNodeOperator(noId);
        assertEq(noAfter.totalExitedKeys, 3);
        assertEq(noAfter.totalDepositedKeys, 5);
        assertEq(noAfter.stuckValidatorsCount, 0);
        assertEq(noAfter.depositableValidatorsCount, 0);
        StakingModuleSummary memory summaryAfter = getStakingModuleSummary();
        assertEq(summaryAfter.totalExitedValidators, 3);
        assertEq(summaryAfter.totalDepositedValidators, 5);
        assertEq(summaryAfter.depositableValidatorsCount, 0);
    }

    function test_unsafeUpdateValidatorsCount_revertWhen_exitedGreaterThanDeposited() public assertInvariants {
        uint256 noId = createNodeOperator(5);
        module.obtainDepositData(5, "");

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.unsafeUpdateValidatorsCount(noId, 6);
    }
}

abstract contract ModuleGetStakingModuleSummary is ModuleFixtures {
    function test_getStakingModuleSummary_depositableValidators() public assertInvariants {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(2);
        StakingModuleSummary memory summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.depositableValidatorsCount, 1);
        assertEq(secondNo.depositableValidatorsCount, 2);
        assertEq(summary.depositableValidatorsCount, 3);
    }

    function test_getStakingModuleSummary_depositedValidators() public assertInvariants {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(2);
        StakingModuleSummary memory summary = getStakingModuleSummary();
        assertEq(summary.totalDepositedValidators, 0);

        module.obtainDepositData(3, "");

        summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.totalDepositedKeys, 1);
        assertEq(secondNo.totalDepositedKeys, 2);
        assertEq(summary.totalDepositedValidators, 3);
    }

    function test_getStakingModuleSummary_exitedValidators() public assertInvariants {
        uint256 first = createNodeOperator(2);
        uint256 second = createNodeOperator(2);
        module.obtainDepositData(4, "");
        StakingModuleSummary memory summary = getStakingModuleSummary();
        assertEq(summary.totalExitedValidators, 0);

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000), bytes8(0x0000000000000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001), bytes16(0x00000000000000000000000000000002))
        );

        summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.totalExitedKeys, 1);
        assertEq(secondNo.totalExitedKeys, 2);
        assertEq(summary.totalExitedValidators, 3);
    }
}

abstract contract ModuleDepositableValidatorsCount is ModuleFixtures {
    function test_depositableValidatorsCountChanges_OnDeposit() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 7);
        module.obtainDepositData(3, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 4);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 4);
    }

    function test_depositableValidatorsCountChanges_OnUnsafeUpdateExitedValidators() public {
        uint256 noId = createNodeOperator(7);
        createNodeOperator(2);
        module.obtainDepositData(4, "");

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        uint256 totalDepositableBefore = getStakingModuleSummary().depositableValidatorsCount;
        module.unsafeUpdateValidatorsCount(noId, 1);
        // values are the same
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, depositableBefore);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, totalDepositableBefore);
    }

    function test_depositableValidatorsCountChanges_OnUnvetKeys() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 nonce = module.getNonce();
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        unvetKeys(noId, 3);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_depositableValidatorsCountChanges_OnWithdrawal() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);

        penalize(noId, BOND_SIZE * 3);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](3);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        validatorInfos[1] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 1,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        validatorInfos[2] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 2,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - BOND_SIZE,
            slashingPenalty: 0,
            isSlashed: false
        }); // Large CL balance drop, that doesn't change the unbonded count.

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 0);
        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 2);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 2);
    }

    function test_depositableValidatorsCountChanges_OnReportGeneralDelayedPenalty() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), (BOND_SIZE * 3) / 2, "Test penalty"); // Lock bond to unbond 2 validators.
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 1);
    }

    function test_depositableValidatorsCountChanges_OnReleaseGeneralDelayedPenalty() public {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE, "Test penalty"); // Lock bond to unbond 2 validators (there's additional fine).
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        module.cancelGeneralDelayedPenalty(noId, accounting.getLockedBondInfo(noId).amount);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
    }

    function test_depositableValidatorsCountChanges_OnRemoveUnvetted() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        unvetKeys(noId, 3);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        vm.prank(nodeOperator);
        module.removeKeys(noId, 3, 1); // Removal charge is applied, hence one key is unbonded.
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 6);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 6);
    }
}

abstract contract ModuleNodeOperatorStateAfterUpdateCurve is ModuleFixtures {
    function updateToBetterCurve() public {
        accounting.updateBondCurve(0, 1.5 ether);
    }

    function updateToWorseCurve() public {
        accounting.updateBondCurve(0, 2.5 ether);
    }

    function test_depositedOnly_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredBefore, requiredAfter, "Required bond should decrease");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0, "Should be no unbonded keys");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_depositedOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredAfter, requiredBefore, "Required bond should increase");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2, "Should be unbonded keys");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredBefore, requiredAfter, "Required bond should decrease");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0, "Should be no unbonded keys");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredAfter, requiredBefore, "Required bond should increase");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2, "Should be unbonded keys");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedDepositedOnly_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredBefore, requiredAfter, "Required bond should decrease");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0);

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_partiallyUnbondedDepositedOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredAfter, requiredBefore, "Required bond should increase");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2);

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_partiallyUnbondedDepositableOnly_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredBefore, requiredAfter, "Required bond should decrease");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0, "Should be no unbonded keys after curve update");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedDepositableOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredAfter, requiredBefore, "Required bond should increase");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2, "Should be unbonded keys after curve update");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredBefore, requiredAfter, "Required bond should decrease");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0, "Should be no unbonded keys after curve update");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 1, "Should be unbonded keys after penalization");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(requiredAfter, requiredBefore, "Required bond should increase");
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2, "Should be unbonded keys after curve update");

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }
}

abstract contract ModuleBatchDepositInfoUpdate is ModuleFixtures {
    function test_batchDepositInfoUpdate() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectEmit(address(module));
        emit IBaseModule.NodeOperatorDepositInfoFullyUpdated();
        uint256 left = module.batchDepositInfoUpdate(3);

        assertEq(left, 0);
    }

    function test_batchDepositInfoUpdate_revertWhen_InvalidInput() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.batchDepositInfoUpdate(0);
    }

    function test_batchDepositInfoUpdate_nothingToUpdate() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        createNodeOperator(1);

        uint256 left = module.batchDepositInfoUpdate(3);

        assertEq(left, 0);
    }

    function test_batchDepositInfoUpdate_partialUpdate() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.recordLogs();
        uint256 left = module.batchDepositInfoUpdate(2);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0);

        assertEq(left, 1);
    }
}
