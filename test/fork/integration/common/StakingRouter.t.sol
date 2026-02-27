// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "src/interfaces/IBaseModule.sol";
import { IStakingRouter } from "src/interfaces/IStakingRouter.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";

import { ExitPenaltyInfo } from "../../../../src/interfaces/IExitPenalties.sol";
import { ModuleTypeBase } from "./ModuleTypeBase.sol";

abstract contract StakingRouterIntegrationTestBase is ModuleTypeBase {
    address internal agent;
    uint256 internal moduleId;
    bool internal isStakingRouterUpgraded;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public virtual {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        agent = stakingRouter.getRoleMember(stakingRouter.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(agent);
        stakingRouter.grantRole(stakingRouter.STAKING_MODULE_MANAGE_ROLE(), agent);
        stakingRouter.grantRole(stakingRouter.REPORT_REWARDS_MINTED_ROLE(), agent);
        stakingRouter.grantRole(stakingRouter.REPORT_EXITED_VALIDATORS_ROLE(), agent);
        stakingRouter.grantRole(stakingRouter.UNSAFE_SET_EXITED_VALIDATORS_ROLE(), agent);
        vm.stopPrank();

        moduleId = findModule();
        isStakingRouterUpgraded = _isStakingRouterUpgraded();
    }

    function moduleDepositWithNoGasMetering(uint256 keysCount) internal returns (uint256 deposited) {
        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();
        vm.startPrank(locator.depositSecurityModule());
        vm.pauseGasMetering();
        if (isStakingRouterUpgraded) {
            _ensureStakingRouterCanDeposit(moduleId);
            stakingRouter.deposit(moduleId, "");
        } else {
            _legacyLidoDeposit(keysCount, moduleId, "");
        }
        vm.resumeGasMetering();
        vm.stopPrank();

        (, uint256 depositedAfter, ) = module.getStakingModuleSummary();
        deposited = depositedAfter - depositedBefore;
    }

    function test_connectCSMToRouter() public view {
        IStakingRouter.StakingModule memory moduleInfo = stakingRouter.getStakingModule(moduleId);
        assertTrue(moduleInfo.stakingModuleAddress == address(module));
    }

    function test_stakingModuleIdIsUnsetOrMatchesModule() public {
        uint256 ejectorModuleId = ejector.stakingModuleId();
        if (ejectorModuleId == 0) {
            (uint256 noId, uint256 keyIndex) = integrationHelpers.getDepositedNodeOperatorWithSequentialActiveKeys(
                nextAddress(),
                1
            );
            address owner = module.getNodeOperatorOwner(noId);

            uint256[] memory keyIndices = new uint256[](1);
            keyIndices[0] = keyIndex;

            uint256 withdrawalRequestFee = IWithdrawalVault(locator.withdrawalVault()).getWithdrawalRequestFee();
            vm.deal(owner, withdrawalRequestFee);
            vm.prank(owner);
            ejector.voluntaryEject{ value: withdrawalRequestFee }(noId, keyIndices, address(this));

            ejectorModuleId = ejector.stakingModuleId();
        }

        assertEq(ejectorModuleId, moduleId);
        IStakingRouter.StakingModule memory moduleInfo = stakingRouter.getStakingModule(ejectorModuleId);
        assertEq(moduleInfo.stakingModuleAddress, address(module));
    }

    function test_RouterDeposit() public assertInvariants {
        (uint256 noId, uint256 keysCount) = integrationHelpers.getDepositableNodeOperator(nextAddress());
        uint256 depositedKeysBefore = module.getNodeOperator(noId).totalDepositedKeys;

        hugeDeposit();

        moduleDepositWithNoGasMetering(keysCount);
        NodeOperator memory no = module.getNodeOperator(noId);
        uint256 deposited = no.totalDepositedKeys - depositedKeysBefore;
        assertGt(deposited, 0);
        if (!isStakingRouterUpgraded) assertEq(deposited, keysCount);
    }

    function test_routerDepositOneBatch() public assertInvariants {
        hugeDeposit();
        uint256 keysCount = 30;
        (, , uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        if (depositableValidatorsCount < keysCount) {
            integrationHelpers.addNodeOperator(nextAddress(), keysCount - depositableValidatorsCount);
        }

        if (isStakingRouterUpgraded) _ensureStakingRouterCanDeposit(moduleId);
        vm.prank(locator.depositSecurityModule());
        vm.startSnapshotGas("CSM.lidoDepositCSM_30keys");
        if (isStakingRouterUpgraded) {
            stakingRouter.deposit(moduleId, "");
        } else {
            _legacyLidoDeposit(keysCount, moduleId, "");
        }
        vm.stopSnapshotGas();
    }

    function test_routerReportRewardsMinted() public assertInvariants {
        uint256 prevShares = lido.sharesOf(address(feeDistributor));

        uint256 ethToStake = 1 ether;
        address dummy = nextAddress();
        vm.startPrank(dummy);
        vm.deal(dummy, ethToStake);
        uint256 rewardsShares = lido.submit{ value: ethToStake }(address(0));
        lido.transferShares(address(module), rewardsShares);
        vm.stopPrank();

        uint256[] memory moduleIds = new uint256[](1);
        uint256[] memory rewards = new uint256[](1);
        moduleIds[0] = moduleId;
        rewards[0] = rewardsShares;

        vm.prank(agent);
        vm.expectCall(address(module), abi.encodeCall(module.onRewardsMinted, (rewardsShares)));
        stakingRouter.reportRewardsMinted(moduleIds, rewards);

        assertEq(lido.sharesOf(address(module)), 0);
        assertEq(lido.sharesOf(address(feeDistributor)), prevShares + rewardsShares);
    }

    function test_decreaseVettedSigningKeysCount() public assertInvariants {
        address nodeOperatorManager = nextAddress();
        uint256 totalKeys = 10;
        uint256 newVetted = 2;
        uint256 noId = integrationHelpers.addNodeOperator(nodeOperatorManager, totalKeys);

        vm.prank(stakingRouter.getRoleMember(stakingRouter.STAKING_MODULE_UNVETTING_ROLE(), 0));
        vm.startSnapshotGas("StakingRouter.decreaseVettedSigningKeysCount");
        stakingRouter.decreaseStakingModuleVettedKeysCountByNodeOperator(
            moduleId,
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(newVetted)
        );
        vm.stopSnapshotGas();

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, newVetted);
        assertEq(no.depositableValidatorsCount, newVetted);
    }

    function test_updateTargetValidatorsLimits() public assertInvariants {
        address nodeOperatorManager = nextAddress();
        uint256 noId = integrationHelpers.addNodeOperator(nodeOperatorManager, 5);

        vm.prank(agent);
        stakingRouter.updateTargetValidatorsLimits(moduleId, noId, 1, 2);

        (uint256 targetLimitMode, uint256 targetValidatorsCount, , , , , , ) = module.getNodeOperatorSummary(noId);
        assertEq(targetLimitMode, 1);
        assertEq(targetValidatorsCount, 2);
    }

    function test_reportStakingModuleExitedValidatorsCountByNodeOperator() public assertInvariants {
        (uint256 noId, uint256 keysCount) = integrationHelpers.getDepositableNodeOperator(nextAddress());
        uint256 exitedKeysBefore = module.getNodeOperator(noId).totalExitedKeys;

        hugeDeposit();

        moduleDepositWithNoGasMetering(keysCount);

        uint256 newExited = exitedKeysBefore + 1;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(newExited)
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, newExited);
    }

    function test_getStakingModuleSummary() public assertInvariants {
        (uint256 noId, uint256 keysCount) = integrationHelpers.getDepositableNodeOperator(nextAddress());

        IStakingRouter.StakingModuleSummary memory summaryOld = stakingRouter.getStakingModuleSummary(moduleId);

        hugeDeposit();

        uint256 depositedDelta = moduleDepositWithNoGasMetering(keysCount);

        uint256 exitedKeysBefore = module.getNodeOperator(noId).totalExitedKeys;
        uint256 newExited = exitedKeysBefore + 1;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(newExited)
        );

        IStakingRouter.StakingModuleSummary memory summary = stakingRouter.getStakingModuleSummary(moduleId);
        assertEq(summary.totalExitedValidators, summaryOld.totalExitedValidators + 1);
        assertEq(summary.totalDepositedValidators, summaryOld.totalDepositedValidators + depositedDelta);
        assertEq(summary.depositableValidatorsCount + depositedDelta, summaryOld.depositableValidatorsCount);
    }

    function test_getNodeOperatorSummary() public assertInvariants {
        (uint256 noId, uint256 keysCount) = integrationHelpers.getDepositableNodeOperator(nextAddress());

        NodeOperator memory no = module.getNodeOperator(noId);

        uint256 depositedValidatorsBefore = no.totalDepositedKeys;
        uint256 depositableValidatorsCount = no.depositableValidatorsCount;
        uint256 exited = no.totalExitedKeys;

        hugeDeposit();
        moduleDepositWithNoGasMetering(keysCount);

        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(++exited)
        );

        IStakingRouter.NodeOperatorSummary memory summary = stakingRouter.getNodeOperatorSummary(moduleId, noId);
        assertEq(summary.targetLimitMode, 0);
        assertEq(summary.targetValidatorsCount, 0);
        assertEq(summary.stuckValidatorsCount, 0);
        assertEq(summary.refundedValidatorsCount, 0);
        assertEq(summary.stuckPenaltyEndTimestamp, 0);
        assertEq(summary.totalExitedValidators, exited);
        uint256 depositedDelta = summary.totalDepositedValidators - depositedValidatorsBefore;
        assertGt(depositedDelta, 0);
        if (!isStakingRouterUpgraded) assertEq(depositedDelta, keysCount);
        assertEq(summary.depositableValidatorsCount + depositedDelta, depositableValidatorsCount);
    }

    function test_unsafeSetExitedValidatorsCount() public assertInvariants {
        hugeDeposit();
        uint256 noId;
        uint256 keysCount;
        uint256 exited;

        for (;;) {
            (noId, keysCount) = integrationHelpers.getDepositableNodeOperator(nextAddress());
            moduleDepositWithNoGasMetering(keysCount);
            NodeOperator memory no = module.getNodeOperator(noId);
            /// we need to be sure there are more than 1 keys for further checks
            if (no.totalDepositedKeys > 1) {
                exited = no.totalExitedKeys;
                break;
            }
        }

        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(++exited)
        );

        IStakingRouter.StakingModule memory moduleInfo = stakingRouter.getStakingModule(moduleId);

        uint256 unsafeExited = exited;

        IStakingRouter.ValidatorsCountsCorrection memory correction = IStakingRouter.ValidatorsCountsCorrection({
            currentModuleExitedValidatorsCount: moduleInfo.exitedValidatorsCount,
            currentNodeOperatorExitedValidatorsCount: exited,
            // dirty hack since prev call does not update total counts
            newModuleExitedValidatorsCount: moduleInfo.exitedValidatorsCount,
            newNodeOperatorExitedValidatorsCount: unsafeExited
        });
        vm.prank(agent);
        stakingRouter.unsafeSetExitedValidatorsCount(moduleId, noId, false, correction);

        assertEq(module.getNodeOperator(noId).totalExitedKeys, unsafeExited);
    }

    function test_reportValidatorExitDelay() public assertInvariants {
        uint256 totalKeys = 1;
        uint256 noId = integrationHelpers.addNodeOperator(nextAddress(), totalKeys);
        bytes memory publicKey = module.getSigningKeys(noId, 0, 1);
        uint256 curveId = accounting.getBondCurveId(noId);
        uint256 exitDelay = parametersRegistry.getAllowedExitDelay(curveId);
        assertFalse(module.isValidatorExitDelayPenaltyApplicable(noId, 12345, publicKey, exitDelay));
        exitDelay += 1;
        assertTrue(module.isValidatorExitDelayPenaltyApplicable(noId, 12345, publicKey, exitDelay));

        vm.prank(stakingRouter.getRoleMember(keccak256("REPORT_VALIDATOR_EXITING_STATUS_ROLE"), 0));
        stakingRouter.reportValidatorExitDelay(moduleId, noId, 12345, publicKey, exitDelay);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties.getExitPenaltyInfo(noId, publicKey);
        uint256 expectedPenalty = parametersRegistry.getExitDelayFee(accounting.getBondCurveId(noId));

        assertTrue(exitPenaltyInfo.delayFee.isValue);
        assertEq(exitPenaltyInfo.delayFee.value, expectedPenalty);
    }

    function _getExpectedRouterDepositRequestCount() internal returns (uint256 expected) {
        if (!isStakingRouterUpgraded) {
            // Skip: request-count logic depends on router-v2 and Lido-v2 deposit interfaces.
            vm.skip(true, "Request-count logic depends on router-v2 and Lido-v2 deposit interfaces");
        }
        uint256 byAmount = stakingRouter.getStakingModuleMaxDepositsCount(moduleId, lido.getDepositableEther());
        uint256 maxPerBlock = stakingRouter.getStakingModuleMaxDepositsPerBlock(moduleId);
        (, , uint256 depositableValidatorsCount) = module.getStakingModuleSummary();

        expected = byAmount;
        if (maxPerBlock < expected) expected = maxPerBlock;
        if (depositableValidatorsCount < expected) expected = depositableValidatorsCount;
    }
}
