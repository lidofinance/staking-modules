// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { ICSModule, NodeOperator } from "../../../src/interfaces/ICSModule.sol";
import { IStakingRouter } from "../../../src/interfaces/IStakingRouter.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { Batch } from "../../../src/lib/QueueLib.sol";
import { ExitPenaltyInfo } from "../../../src/interfaces/ICSExitPenalties.sol";

contract StakingRouterIntegrationTest is
    Test,
    Utilities,
    DeploymentFixtures,
    InvariantAsserts
{
    address internal agent;
    uint256 internal moduleId;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = csm.getNodeOperatorsCount();
        assertModuleKeys(csm);
        assertModuleEnqueuedCount(csm);
        assertModuleUnusedStorageSlots(csm);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(
            lido,
            address(accounting),
            locator.burner()
        );
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        vm.startPrank(csm.getRoleMember(csm.DEFAULT_ADMIN_ROLE(), 0));
        csm.grantRole(csm.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        agent = stakingRouter.getRoleMember(
            stakingRouter.DEFAULT_ADMIN_ROLE(),
            0
        );
        vm.startPrank(agent);
        stakingRouter.grantRole(
            stakingRouter.STAKING_MODULE_MANAGE_ROLE(),
            agent
        );
        stakingRouter.grantRole(
            stakingRouter.REPORT_REWARDS_MINTED_ROLE(),
            agent
        );
        stakingRouter.grantRole(
            stakingRouter.REPORT_EXITED_VALIDATORS_ROLE(),
            agent
        );
        stakingRouter.grantRole(
            stakingRouter.UNSAFE_SET_EXITED_VALIDATORS_ROLE(),
            agent
        );
        vm.stopPrank();

        moduleId = findCSModule();
    }

    function lidoDepositWithNoGasMetering(uint256 keysCount) internal {
        vm.startPrank(locator.depositSecurityModule());
        vm.pauseGasMetering();
        lido.deposit(keysCount, moduleId, "");
        vm.resumeGasMetering();
        vm.stopPrank();
    }

    function test_connectCSMToRouter() public view {
        IStakingRouter.StakingModule memory module = stakingRouter
            .getStakingModule(moduleId);
        assertTrue(module.stakingModuleAddress == address(csm));
    }

    function test_validStakingModuleId() public view {
        IStakingRouter.StakingModule memory module = stakingRouter
            .getStakingModule(ejector.STAKING_MODULE_ID());
        assertEq(module.stakingModuleAddress, address(csm));
    }

    function test_RouterDeposit() public assertInvariants {
        (uint256 noId, uint256 keysCount) = getDepositableNodeOperator(
            nextAddress()
        );
        uint256 depositedKeysBefore = csm
            .getNodeOperator(noId)
            .totalDepositedKeys;

        hugeDeposit();

        lidoDepositWithNoGasMetering(keysCount);
        NodeOperator memory no = csm.getNodeOperator(noId);
        assertEq(no.totalDepositedKeys, depositedKeysBefore + keysCount);
    }

    function test_routerDepositOneBatch() public assertInvariants {
        hugeDeposit();
        uint256 keysCount = 30;
        (, , uint256 depositableValidatorsCount) = csm
            .getStakingModuleSummary();
        if (depositableValidatorsCount < keysCount) {
            addNodeOperator(
                nextAddress(),
                keysCount - depositableValidatorsCount
            );
        }

        vm.prank(locator.depositSecurityModule());
        vm.startSnapshotGas("CSM.lidoDepositCSM_30keys");
        lido.deposit(keysCount, moduleId, "");
        vm.stopSnapshotGas();
    }

    function test_routerReportRewardsMinted() public assertInvariants {
        uint256 prevShares = lido.sharesOf(address(feeDistributor));

        uint256 ethToStake = 1 ether;
        address dummy = nextAddress();
        vm.startPrank(dummy);
        vm.deal(dummy, ethToStake);
        uint256 rewardsShares = lido.submit{ value: ethToStake }(address(0));
        lido.transferShares(address(csm), rewardsShares);
        vm.stopPrank();

        uint256[] memory moduleIds = new uint256[](1);
        uint256[] memory rewards = new uint256[](1);
        moduleIds[0] = moduleId;
        rewards[0] = rewardsShares;

        vm.prank(agent);
        vm.expectCall(
            address(csm),
            abi.encodeCall(csm.onRewardsMinted, (rewardsShares))
        );
        stakingRouter.reportRewardsMinted(moduleIds, rewards);

        assertEq(lido.sharesOf(address(csm)), 0);
        assertEq(
            lido.sharesOf(address(feeDistributor)),
            prevShares + rewardsShares
        );
    }

    function test_updateTargetValidatorsLimits() public assertInvariants {
        address nodeOperatorManager = nextAddress();
        uint256 noId = addNodeOperator(nodeOperatorManager, 5);

        vm.prank(agent);
        stakingRouter.updateTargetValidatorsLimits(moduleId, noId, 1, 2);

        (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            ,
            ,
            ,
            ,
            ,

        ) = csm.getNodeOperatorSummary(noId);
        assertEq(targetLimitMode, 1);
        assertEq(targetValidatorsCount, 2);
    }

    function test_reportStakingModuleExitedValidatorsCountByNodeOperator()
        public
        assertInvariants
    {
        (uint256 noId, uint256 keysCount) = getDepositableNodeOperator(
            nextAddress()
        );
        uint256 exitedKeysBefore = csm.getNodeOperator(noId).totalExitedKeys;

        hugeDeposit();

        lidoDepositWithNoGasMetering(keysCount);

        uint256 newExited = exitedKeysBefore + 1;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(newExited)))
        );

        NodeOperator memory no = csm.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, newExited);
    }

    function test_getStakingModuleSummary() public assertInvariants {
        (uint256 noId, uint256 keysCount) = getDepositableNodeOperator(
            nextAddress()
        );

        IStakingRouter.StakingModuleSummary memory summaryOld = stakingRouter
            .getStakingModuleSummary(moduleId);

        hugeDeposit();

        lidoDepositWithNoGasMetering(keysCount);

        uint256 exitedKeysBefore = csm.getNodeOperator(noId).totalExitedKeys;
        uint256 newExited = exitedKeysBefore + 1;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(newExited)))
        );

        IStakingRouter.StakingModuleSummary memory summary = stakingRouter
            .getStakingModuleSummary(moduleId);
        assertEq(
            summary.totalExitedValidators,
            summaryOld.totalExitedValidators + 1
        );
        assertEq(
            summary.totalDepositedValidators,
            summaryOld.totalDepositedValidators + keysCount
        );
        assertEq(
            summary.depositableValidatorsCount,
            summaryOld.depositableValidatorsCount - keysCount
        );
    }

    function test_getNodeOperatorSummary() public assertInvariants {
        (uint256 noId, uint256 keysCount) = getDepositableNodeOperator(
            nextAddress()
        );
        uint256 depositedValidatorsBefore = csm
            .getNodeOperator(noId)
            .totalDepositedKeys;
        uint256 depositableValidatorsCount = csm
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        hugeDeposit();
        lidoDepositWithNoGasMetering(keysCount);

        uint256 exited = 1;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(exited)))
        );

        IStakingRouter.NodeOperatorSummary memory summary = stakingRouter
            .getNodeOperatorSummary(moduleId, noId);
        assertEq(summary.targetLimitMode, 0);
        assertEq(summary.targetValidatorsCount, 0);
        assertEq(summary.stuckValidatorsCount, 0);
        assertEq(summary.refundedValidatorsCount, 0);
        assertEq(summary.stuckPenaltyEndTimestamp, 0);
        assertEq(summary.totalExitedValidators, exited);
        assertEq(
            summary.totalDepositedValidators,
            depositedValidatorsBefore + keysCount
        );
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCount - keysCount
        );
    }

    function test_unsafeSetExitedValidatorsCount() public assertInvariants {
        hugeDeposit();
        uint256 noId;
        uint256 keysCount;

        for (;;) {
            (noId, keysCount) = getDepositableNodeOperator(nextAddress());
            lidoDepositWithNoGasMetering(keysCount);
            /// we need to be sure there are more than 1 keys for further checks
            if (csm.getNodeOperator(noId).totalDepositedKeys > 1) {
                break;
            }
        }

        uint256 exited = 2;
        vm.prank(agent);
        stakingRouter.reportStakingModuleExitedValidatorsCountByNodeOperator(
            moduleId,
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(exited)))
        );

        IStakingRouter.StakingModule memory moduleInfo = stakingRouter
            .getStakingModule(moduleId);

        uint256 unsafeExited = 1;

        IStakingRouter.ValidatorsCountsCorrection
            memory correction = IStakingRouter.ValidatorsCountsCorrection({
                currentModuleExitedValidatorsCount: moduleInfo
                    .exitedValidatorsCount,
                currentNodeOperatorExitedValidatorsCount: exited,
                // dirty hack since prev call does not update total counts
                newModuleExitedValidatorsCount: moduleInfo
                    .exitedValidatorsCount,
                newNodeOperatorExitedValidatorsCount: unsafeExited
            });
        vm.prank(agent);
        stakingRouter.unsafeSetExitedValidatorsCount(
            moduleId,
            noId,
            false,
            correction
        );

        NodeOperator memory no = csm.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, unsafeExited);
    }

    function test_decreaseVettedSigningKeysCount() public assertInvariants {
        address nodeOperatorManager = nextAddress();
        uint256 totalKeys = 10;
        uint256 newVetted = 2;
        uint256 noId = addNodeOperator(nodeOperatorManager, totalKeys);

        vm.prank(
            stakingRouter.getRoleMember(
                stakingRouter.STAKING_MODULE_UNVETTING_ROLE(),
                0
            )
        );
        vm.startSnapshotGas("CSM.decreaseVettedSigningKeysCount");
        stakingRouter.decreaseStakingModuleVettedKeysCountByNodeOperator(
            moduleId,
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(newVetted)))
        );
        vm.stopSnapshotGas();

        NodeOperator memory no = csm.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, newVetted);
        assertEq(no.depositableValidatorsCount, newVetted);
    }

    function test_reportValidatorExitDelay() public assertInvariants {
        uint256 totalKeys = 1;
        uint256 noId = addNodeOperator(nextAddress(), totalKeys);
        bytes memory publicKey = csm.getSigningKeys(noId, 0, 1);
        uint256 curveId = accounting.getBondCurveId(noId);
        uint256 exitDelay = parametersRegistry.getAllowedExitDelay(curveId);
        assertFalse(
            csm.isValidatorExitDelayPenaltyApplicable(
                noId,
                12345,
                publicKey,
                exitDelay
            )
        );
        exitDelay += 1;
        assertTrue(
            csm.isValidatorExitDelayPenaltyApplicable(
                noId,
                12345,
                publicKey,
                exitDelay
            )
        );

        vm.prank(
            stakingRouter.getRoleMember(
                keccak256("REPORT_VALIDATOR_EXITING_STATUS_ROLE"),
                0
            )
        );
        stakingRouter.reportValidatorExitDelay(
            moduleId,
            noId,
            12345,
            publicKey,
            exitDelay
        );

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        uint256 expectedPenalty = parametersRegistry.getExitDelayFee(
            accounting.getBondCurveId(noId)
        );

        assertTrue(exitPenaltyInfo.delayFee.isValue);
        assertEq(exitPenaltyInfo.delayFee.value, expectedPenalty);
    }
}
