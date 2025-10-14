// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { DeployParams } from "../../../script/DeployBase.s.sol";
import { HashConsensus } from "../../../src/lib/base-oracle/HashConsensus.sol";
import { BaseOracle } from "../../../src/lib/base-oracle/BaseOracle.sol";
import { Slot } from "../../../src/lib/Types.sol";
import { OssifiableProxy } from "../../../src/lib/proxy/OssifiableProxy.sol";
import { NodeOperator } from "../../../src/interfaces/ICSModule.sol";
import { ICSBondLock } from "../../../src/interfaces/ICSBondLock.sol";
import { ICSParametersRegistry } from "../../../src/interfaces/ICSParametersRegistry.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";

contract V2UpgradeTestBase is
    Test,
    Utilities,
    DeploymentFixtures,
    InvariantAsserts
{
    uint256 internal forkIdBeforeUpgrade;
    uint256 internal forkIdAfterUpgrade;

    error UpdateConfigRequired();

    function setUp() public {
        Env memory env = envVars();
        assertNotEq(env.VOTE_PREV_BLOCK, 0, "VOTE_PREV_BLOCK not set");
        forkIdBeforeUpgrade = vm.createFork(env.RPC_URL, env.VOTE_PREV_BLOCK);
        forkIdAfterUpgrade = vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }
}

contract VoteChangesTest is V2UpgradeTestBase {
    function test_csmChanges() public {
        OssifiableProxy csmProxy = OssifiableProxy(payable(address(csm)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = csmProxy.proxy__getImplementation();
        address verifierBefore = csm.getRoleMember(csm.VERIFIER_ROLE(), 0);
        address gateSealBefore = csm.getRoleMember(csm.PAUSE_ROLE(), 0);

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = csmProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(csmImpl));

        assertTrue(
            csm.hasRole(csm.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate))
        );
        assertTrue(
            csm.hasRole(
                csm.CREATE_NODE_OPERATOR_ROLE(),
                address(permissionlessGate)
            )
        );

        assertFalse(csm.hasRole(csm.VERIFIER_ROLE(), verifierBefore));
        assertTrue(csm.hasRole(csm.VERIFIER_ROLE(), address(verifier)));

        assertFalse(csm.hasRole(csm.PAUSE_ROLE(), gateSealBefore));
        assertTrue(csm.hasRole(csm.PAUSE_ROLE(), address(gateSeal)));

        assertEq(csm.getRoleMemberCount(keccak256("MODULE_MANAGER_ROLE")), 0);

        assertEq(csm.getInitializedVersion(), 2);

        assertFalse(
            csm.depositQueueItem(csm.QUEUE_LEGACY_PRIORITY(), 0).isNil()
        );
    }

    function test_csmState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        address accountingBefore = address(csm.accounting());
        uint256 nonceBefore = csm.getNonce();
        (
            uint256 totalExitedValidatorsBefore,
            uint256 totalDepositedValidatorsBefore,
            uint256 depositableValidatorsCountBefore
        ) = csm.getStakingModuleSummary();
        uint256 totalNodeOperatorsBefore = csm.getNodeOperatorsCount();

        vm.selectFork(forkIdAfterUpgrade);
        address accountingAfter = address(csm.accounting());
        uint256 nonceAfter = csm.getNonce();
        (
            uint256 totalExitedValidatorsAfter,
            uint256 totalDepositedValidatorsAfter,
            uint256 depositableValidatorsCountAfter
        ) = csm.getStakingModuleSummary();
        uint256 totalNodeOperatorsAfter = csm.getNodeOperatorsCount();

        assertEq(accountingBefore, accountingAfter);
        assertEq(nonceBefore, nonceAfter);
        assertEq(totalExitedValidatorsBefore, totalExitedValidatorsAfter);
        assertEq(totalDepositedValidatorsBefore, totalDepositedValidatorsAfter);
        assertEq(
            depositableValidatorsCountBefore,
            depositableValidatorsCountAfter
        );
        assertEq(totalNodeOperatorsBefore, totalNodeOperatorsAfter);
    }

    function test_csmNodeOperatorsState() public {
        if (skipInvariants()) {
            return;
        }
        NodeOperator memory noBefore;
        NodeOperator memory noAfter;
        for (uint256 noId = 0; noId < csm.getNodeOperatorsCount(); noId++) {
            noBefore = csm.getNodeOperator(noId);
            vm.selectFork(forkIdAfterUpgrade);
            noAfter = csm.getNodeOperator(noId);

            assertEq(
                noBefore.totalAddedKeys,
                noAfter.totalAddedKeys,
                "totalAddedKeys"
            );
            assertEq(
                noBefore.totalWithdrawnKeys,
                noAfter.totalWithdrawnKeys,
                "totalWithdrawnKeys"
            );
            assertEq(
                noBefore.totalDepositedKeys,
                noAfter.totalDepositedKeys,
                "totalDepositedKeys"
            );
            assertEq(
                noBefore.totalVettedKeys,
                noAfter.totalVettedKeys,
                "totalVettedKeys"
            );
            assertEq(
                noBefore.stuckValidatorsCount,
                noAfter.stuckValidatorsCount,
                "stuckValidatorsCount"
            );
            assertEq(
                noBefore.depositableValidatorsCount,
                noAfter.depositableValidatorsCount,
                "depositableValidatorsCount"
            );
            assertEq(noBefore.targetLimit, noAfter.targetLimit, "targetLimit");
            assertEq(
                noBefore.targetLimitMode,
                noAfter.targetLimitMode,
                "targetLimitMode"
            );
            assertEq(
                noBefore.totalExitedKeys,
                noAfter.totalExitedKeys,
                "totalExitedKeys"
            );
            assertEq(
                noBefore.enqueuedCount,
                noAfter.enqueuedCount,
                "enqueuedCount"
            );
            assertEq(
                noBefore.managerAddress,
                noAfter.managerAddress,
                "managerAddress"
            );
            assertEq(
                noBefore.proposedManagerAddress,
                noAfter.proposedManagerAddress,
                "proposedManagerAddress"
            );
            assertEq(
                noBefore.rewardAddress,
                noAfter.rewardAddress,
                "rewardAddress"
            );
            assertEq(
                noBefore.proposedRewardAddress,
                noAfter.proposedRewardAddress,
                "proposedRewardAddress"
            );
            assertEq(
                noBefore.extendedManagerPermissions,
                noAfter.extendedManagerPermissions,
                "extendedManagerPermissions"
            );
        }
    }

    function test_accountingChanges() public {
        OssifiableProxy accountingProxy = OssifiableProxy(
            payable(address(accounting))
        );

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = accountingProxy.proxy__getImplementation();
        address gateSealBefore = accounting.getRoleMember(
            accounting.PAUSE_ROLE(),
            0
        );

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = accountingProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(accountingImpl));

        assertTrue(
            accounting.hasRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(vettedGate)
            )
        );
        assertFalse(
            accounting.hasRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(permissionlessGate)
            )
        );
        assertFalse(
            accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(csm))
        );

        assertFalse(
            accounting.hasRole(accounting.PAUSE_ROLE(), gateSealBefore)
        );
        assertTrue(
            accounting.hasRole(accounting.PAUSE_ROLE(), address(gateSeal))
        );

        assertEq(
            accounting.getRoleMemberCount(keccak256("ACCOUNTING_MANAGER_ROLE")),
            0
        );
        assertEq(
            accounting.getRoleMemberCount(keccak256("RESET_BOND_CURVE_ROLE")),
            0
        );

        assertEq(accounting.getInitializedVersion(), 2);
    }

    function test_accountingState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        address feeDistributorBefore = address(accounting.feeDistributor());
        address chargePenaltyRecipientBefore = address(
            accounting.chargePenaltyRecipient()
        );
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.selectFork(forkIdAfterUpgrade);
        address feeDistributorAfter = address(accounting.feeDistributor());
        address chargePenaltyRecipientAfter = address(
            accounting.chargePenaltyRecipient()
        );
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(feeDistributorBefore, feeDistributorAfter);
        assertEq(chargePenaltyRecipientBefore, chargePenaltyRecipientAfter);
        assertEq(totalBondSharesBefore, totalBondSharesAfter);
    }

    function test_accountingCurvesState() public {
        if (skipInvariants()) {
            return;
        }
        uint16[12] memory keysCounts = [
            0,
            1,
            2,
            4,
            8,
            16,
            32,
            64,
            128,
            256,
            512,
            1024
        ];
        uint256 bondAmountBefore;
        uint256 bondAmountAfter;

        bytes32 bondCurveStorageLocation = 0x8f22e270e477f5becb8793b61d439ab7ae990ed8eba045eb72061c0e6cfe1500;
        // bondCurvesCount after upgrade might be different but all existing curves must be migrated
        uint256 bondCurvesCountBefore = uint256(
            vm.load(address(accounting), bondCurveStorageLocation)
        );
        assertNotEq(bondCurvesCountBefore, 0);

        for (uint256 curveId = 0; curveId < bondCurvesCountBefore; curveId++) {
            for (uint256 i = 0; i < keysCounts.length; i++) {
                vm.selectFork(forkIdBeforeUpgrade);
                bondAmountBefore = accounting.getBondAmountByKeysCount(
                    keysCounts[i],
                    curveId
                );
                vm.selectFork(forkIdAfterUpgrade);
                bondAmountAfter = accounting.getBondAmountByKeysCount(
                    keysCounts[i],
                    curveId
                );
                assertEq(
                    bondAmountBefore,
                    bondAmountAfter,
                    "bond amount for keysCount"
                );
            }
        }
    }

    function test_accountingNodeOperatorsState() public {
        if (skipInvariants()) {
            return;
        }
        uint256 curveBefore;
        uint256 curveAfter;
        uint256 bondBefore;
        uint256 requiredBefore;
        uint256 bondAfter;
        uint256 requiredAfter;
        ICSBondLock.BondLock memory bondLockBefore;
        ICSBondLock.BondLock memory bondLockAfter;
        for (uint256 noId = 0; noId < csm.getNodeOperatorsCount(); noId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            curveBefore = accounting.getBondCurveId(noId);
            (bondBefore, requiredBefore) = accounting.getBondSummary(noId);
            bondLockBefore = accounting.getLockedBondInfo(noId);

            vm.selectFork(forkIdAfterUpgrade);
            curveAfter = accounting.getBondCurveId(noId);
            (bondAfter, requiredAfter) = accounting.getBondSummary(noId);
            bondLockAfter = accounting.getLockedBondInfo(noId);

            assertEq(curveBefore, curveAfter, "bond curve");
            assertEq(bondBefore, bondAfter, "bond amount");
            assertEq(requiredBefore, requiredAfter, "required bond amount");
            assertEq(
                bondLockBefore.amount,
                bondLockAfter.amount,
                "bond lock amount"
            );
            assertEq(
                bondLockBefore.until,
                bondLockAfter.until,
                "bond lock until"
            );
        }
    }

    function test_feeDistributorChanges() public {
        OssifiableProxy feeDistributorProxy = OssifiableProxy(
            payable(address(feeDistributor))
        );
        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = feeDistributorProxy.proxy__getImplementation();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = feeDistributorProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(feeDistributorImpl));

        assertEq(feeDistributor.getInitializedVersion(), 2);
        assertEq(feeDistributor.rebateRecipient(), locator.treasury());
    }

    function test_feeDistributorState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        bytes32 treeRootBefore = feeDistributor.treeRoot();
        string memory treeCidBefore = feeDistributor.treeCid();
        string memory logCidBefore = feeDistributor.logCid();
        uint256 totalClaimableSharesBefore = feeDistributor
            .totalClaimableShares();

        vm.selectFork(forkIdAfterUpgrade);
        bytes32 treeRootAfter = feeDistributor.treeRoot();
        string memory treeCidAfter = feeDistributor.treeCid();
        string memory logCidAfter = feeDistributor.logCid();
        uint256 totalClaimableSharesAfter = feeDistributor
            .totalClaimableShares();

        assertEq(treeRootBefore, treeRootAfter);
        assertEq(
            keccak256(bytes(treeCidBefore)),
            keccak256(bytes(treeCidAfter))
        );
        assertEq(keccak256(bytes(logCidBefore)), keccak256(bytes(logCidAfter)));
        assertEq(totalClaimableSharesBefore, totalClaimableSharesAfter);
    }

    function test_feeDistributorNodeOperatorState() public {
        if (skipInvariants()) {
            return;
        }
        uint256 distributedSharesBefore;
        uint256 distributedSharesAfter;
        for (uint256 noId = 0; noId < csm.getNodeOperatorsCount(); noId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            distributedSharesBefore = feeDistributor.distributedShares(noId);

            vm.selectFork(forkIdAfterUpgrade);
            distributedSharesAfter = feeDistributor.distributedShares(noId);

            assertEq(
                distributedSharesBefore,
                distributedSharesAfter,
                "distributed shares"
            );
        }
    }

    function test_feeOracleChanges() public {
        OssifiableProxy oracleProxy = OssifiableProxy(payable(address(oracle)));
        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = oracleProxy.proxy__getImplementation();
        address gateSealBefore = oracle.getRoleMember(oracle.PAUSE_ROLE(), 0);

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = oracleProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(oracleImpl));

        assertFalse(oracle.hasRole(oracle.PAUSE_ROLE(), gateSealBefore));
        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), address(gateSeal)));

        assertEq(oracle.getContractVersion(), 2);
        assertEq(oracle.getConsensusVersion(), 3);

        assertEq(
            oracle.getRoleMemberCount(keccak256("CONTRACT_MANAGER_ROLE")),
            0
        );
    }
}
