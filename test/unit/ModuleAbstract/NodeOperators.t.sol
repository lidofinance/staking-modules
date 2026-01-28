// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { console } from "forge-std/console.sol";
import { Test, Vm } from "forge-std/Test.sol";

import { Batch } from "src/lib/DepositQueueLib.sol";
import { BaseModule } from "src/abstract/BaseModule.sol";
import { BondLock } from "src/abstract/BondLock.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IExitPenalties, ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IGeneralPenalty } from "src/lib/GeneralPenaltyLib.sol";
import { ILidoLocator } from "src/interfaces/ILidoLocator.sol";
import { INOAddresses } from "src/lib/NOAddresses.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { AccountingMock } from "../../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../../helpers/mocks/ParametersRegistryMock.sol";
import { ERC20Testable } from "../../helpers/ERCTestable.sol";
import { ExitPenaltiesMock } from "../../helpers/mocks/ExitPenaltiesMock.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { Stub } from "../../helpers/mocks/Stub.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleCreateNodeOperator is ModuleFixtures {
    function test_createNodeOperator() public assertInvariants {
        uint256 nonce = module.getNonce();
        vm.expectEmit(address(module));
        emit IBaseModule.NodeOperatorAdded(
            0,
            nodeOperator,
            nodeOperator,
            false
        );

        uint256 nodeOperatorId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
        assertEq(module.getNodeOperatorsCount(), 1);
        assertEq(module.getNonce(), nonce + 1);
        assertEq(nodeOperatorId, 0);
    }

    function test_createNodeOperator_withCustomAddresses()
        public
        assertInvariants
    {
        address manager = address(154);
        address reward = address(42);

        vm.expectEmit(address(module));
        emit IBaseModule.NodeOperatorAdded(0, manager, reward, false);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, reward);
        assertEq(no.extendedManagerPermissions, false);
    }

    function test_createNodeOperator_withExtendedManagerPermissions()
        public
        assertInvariants
    {
        address manager = address(154);
        address reward = address(42);

        vm.expectEmit(address(module));
        emit IBaseModule.NodeOperatorAdded(0, manager, reward, true);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: true
            }),
            address(0)
        );

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, reward);
        assertEq(no.extendedManagerPermissions, true);
    }

    function test_createNodeOperator_withReferrer() public assertInvariants {
        {
            vm.expectEmit(address(module));
            emit IBaseModule.NodeOperatorAdded(
                0,
                nodeOperator,
                nodeOperator,
                false
            );
            vm.expectEmit(address(module));
            emit IBaseModule.ReferrerSet(0, address(154));
        }
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(154)
        );
    }

    function test_createNodeOperator_RevertWhen_ZeroSenderAddress() public {
        vm.expectRevert(IBaseModule.ZeroSenderAddress.selector);
        module.createNodeOperator(
            address(0),
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_createNodeOperator_multipleInSameTx() public {
        address manager = nextAddress("MANAGER");
        address referrer = nextAddress("REFERRER");
        NodeOperatorManagementProperties
            memory props = NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: address(0),
                extendedManagerPermissions: false
            });
        uint256 nonceBefore = module.getNonce();
        uint256 countBefore = module.getNodeOperatorsCount();

        // Act: create two node operators in the same transaction
        uint256 id1 = module.createNodeOperator(manager, props, referrer);
        uint256 id2 = module.createNodeOperator(manager, props, referrer);

        // Assert: both created, ids are sequential, nonce incremented twice
        assertEq(id1, countBefore);
        assertEq(id2, countBefore + 1);
        assertEq(module.getNodeOperatorsCount(), countBefore + 2);
        assertEq(module.getNonce(), nonceBefore + 2);
        // Check events and referrer
        NodeOperator memory no1 = module.getNodeOperator(id1);
        assertEq(no1.managerAddress, manager);
        NodeOperator memory no2 = module.getNodeOperator(id2);
        assertEq(no2.managerAddress, manager);
    }
}

abstract contract ModuleGetNodeOperatorNonWithdrawnKeys is ModuleFixtures {
    function test_getNodeOperatorNonWithdrawnKeys() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(noId);
        assertEq(keys, 3);
    }

    function test_getNodeOperatorNonWithdrawnKeys_WithdrawnKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportRegularWithdrawnValidators(validatorInfos);
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(noId);
        assertEq(keys, 2);
    }

    function test_getNodeOperatorNonWithdrawnKeys_ZeroWhenNoNodeOperator()
        public
        view
    {
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(0);
        assertEq(keys, 0);
    }
}

abstract contract ModuleGetNodeOperatorSummary is ModuleFixtures {
    function test_getNodeOperatorSummary_defaultValues()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0);
        assertEq(summary.targetValidatorsCount, 0); // ?
        assertEq(summary.stuckValidatorsCount, 0);
        assertEq(summary.refundedValidatorsCount, 0);
        assertEq(summary.stuckPenaltyEndTimestamp, 0);
        assertEq(summary.totalExitedValidators, 0);
        assertEq(summary.totalDepositedValidators, 0);
        assertEq(summary.depositableValidatorsCount, 1);
    }

    function test_getNodeOperatorSummary_depositedKey()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(2);

        module.obtainDepositData(1, "");

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.depositableValidatorsCount, 1);
        assertEq(summary.totalDepositedValidators, 1);
    }

    function test_getNodeOperatorSummary_softTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitAndDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitAboveTotalKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 5);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            5,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 2, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitAndDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 2, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitAboveTotalKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 2, 5);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            5,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitEqualToDepositedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitLowerThanDepositedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitLowerThanVettedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            2,
            "depositableValidatorsCount mismatch"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 3); // Should NOT be unvetted.
    }

    function test_getNodeOperatorSummary_targetLimitHigherThanVettedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 9);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            9,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_noTargetLimitDueToLockedBond()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(3, "");

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitDueToUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_noTargetLimitDueToUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitDueToAllUnbonded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        penalize(noId, BOND_SIZE * 3);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitLowerThanUnbonded()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitLowerThanUnbonded_deposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 2, 2);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitGreaterThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitGreaterThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(4, "");

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            3,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitEqualUnbonded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            4,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitLowerThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 1, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitLowerThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(5, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitGreaterThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 1, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitGreaterThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(4, "");

        module.updateTargetValidatorsLimits(noId, 1, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            3,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedGreaterThanTotalMinusDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE * 3);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedEqualToTotalMinusDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE * 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedGreaterThanTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 4);

        penalize(noId, BOND_SIZE * 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedEqualToTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 4);

        penalize(noId, BOND_SIZE);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            4,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedLessThanTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 3);

        penalize(noId, BOND_SIZE);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }
}

abstract contract ModuleGetNodeOperator is ModuleFixtures {
    function test_getNodeOperator() public assertInvariants {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_getNodeOperator_WhenNoNodeOperator() public assertInvariants {
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, address(0));
        assertEq(no.rewardAddress, address(0));
    }
}

abstract contract ModuleProposeNodeOperatorManagerAddressChange is
    ModuleFixtures
{
    function test_proposeNodeOperatorManagerAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChangeProposed(
            noId,
            address(0),
            stranger
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorManagerAddressChange_proposeNew() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChangeProposed(
            noId,
            stranger,
            strangerNumberTwo
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, strangerNumberTwo);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.proposeNodeOperatorManagerAddressChange(0, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_NotManager()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_AlreadyProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.AlreadyProposed.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_SameAddressProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, nodeOperator);
    }
}

abstract contract ModuleConfirmNodeOperatorManagerAddressChange is
    ModuleFixtures
{
    function test_confirmNodeOperatorManagerAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.confirmNodeOperatorManagerAddressChange(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, stranger);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.confirmNodeOperatorManagerAddressChange(0);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_NotProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(stranger);
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_OtherProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(nextAddress());
        module.confirmNodeOperatorManagerAddressChange(noId);
    }
}

abstract contract ModuleProposeNodeOperatorRewardAddressChange is
    ModuleFixtures
{
    function test_proposeNodeOperatorRewardAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChangeProposed(
            noId,
            address(0),
            stranger
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorRewardAddressChange_proposeNew() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChangeProposed(
            noId,
            stranger,
            strangerNumberTwo
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, strangerNumberTwo);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.proposeNodeOperatorRewardAddressChange(0, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_NotRewardAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotRewardAddress.selector);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_AlreadyProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.AlreadyProposed.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_SameAddressProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, nodeOperator);
    }
}

abstract contract ModuleConfirmNodeOperatorRewardAddressChange is
    ModuleFixtures
{
    function test_confirmNodeOperatorRewardAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.confirmNodeOperatorRewardAddressChange(0);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_NotProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_OtherProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(nextAddress());
        module.confirmNodeOperatorRewardAddressChange(noId);
    }
}

abstract contract ModuleResetNodeOperatorManagerAddress is ModuleFixtures {
    function test_resetNodeOperatorManagerAddress() public {
        uint256 noId = createNodeOperator();

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.resetNodeOperatorManagerAddress(noId);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, stranger);
        assertEq(no.rewardAddress, stranger);
    }

    function test_resetNodeOperatorManagerAddress_proposedManagerAddressIsReset()
        public
    {
        uint256 noId = createNodeOperator();
        address manager = nextAddress("MANAGER");

        vm.startPrank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, manager);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        vm.stopPrank();

        vm.startPrank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);
        module.resetNodeOperatorManagerAddress(noId);
        vm.stopPrank();

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(manager);
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.resetNodeOperatorManagerAddress(0);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_NotRewardAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotRewardAddress.selector);
        vm.prank(stranger);
        module.resetNodeOperatorManagerAddress(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_SameAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.resetNodeOperatorManagerAddress(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_ExtendedPermissions()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.MethodCallIsNotAllowed.selector);
        vm.prank(nodeOperator);
        module.resetNodeOperatorManagerAddress(noId);
    }
}

abstract contract ModuleChangeNodeOperatorRewardAddress is ModuleFixtures {
    function test_changeNodeOperatorRewardAddress() public {
        uint256 noId = createNodeOperator(true);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, stranger);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
    }

    function test_changeNodeOperatorRewardAddress_proposedRewardAddressReset()
        public
    {
        uint256 noId = createNodeOperator(true);

        vm.startPrank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, nextAddress());
        module.changeNodeOperatorRewardAddress(noId, stranger);
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
        assertEq(no.proposedRewardAddress, address(0));
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(0, stranger);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_SameAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, nodeOperator);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_ZeroRewardAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.ZeroRewardAddress.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, address(0));
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NotManagerAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        vm.prank(stranger);
        module.changeNodeOperatorRewardAddress(noId, stranger);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_SenderIsRewardAddress()
        public
    {
        uint256 noId = createNodeOperator(nodeOperator, stranger, true);

        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        vm.prank(stranger);
        module.changeNodeOperatorRewardAddress(noId, nodeOperator);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NoExtendedPermissions()
        public
    {
        uint256 noId = createNodeOperator(false);
        vm.expectRevert(INOAddresses.MethodCallIsNotAllowed.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, stranger);
    }
}

abstract contract ModuleCreateNodeOperators is ModuleFixtures {
    function createMultipleOperatorsWithKeysETH(
        uint256 operators,
        uint256 keysCount,
        address managerAddress
    ) external payable {
        for (uint256 i; i < operators; i++) {
            uint256 noId = module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: false
                }),
                address(0)
            );
            uint256 amount = module.ACCOUNTING().getRequiredBondForNextKeys(
                noId,
                keysCount
            );
            (bytes memory keys, bytes memory signatures) = keysSignatures(
                keysCount
            );
            module.addValidatorKeysETH{ value: amount }(
                managerAddress,
                noId,
                keysCount,
                keys,
                signatures
            );
        }
    }
}
