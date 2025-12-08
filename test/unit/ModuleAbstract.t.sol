// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { console } from "forge-std/console.sol";
import { Test, Vm } from "forge-std/Test.sol";

import { Batch } from "src/lib/QueueLib.sol";
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
import { INodeOperatorOwner } from "src/interfaces/INodeOperatorOwner.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ERC20Testable } from "../helpers/ERCTestable.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { InvariantAsserts } from "../helpers/InvariantAsserts.sol";
import { LidoLocatorMock } from "../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../helpers/mocks/LidoMock.sol";
import { Stub } from "../helpers/mocks/Stub.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { WstETHMock } from "../helpers/mocks/WstETHMock.sol";

abstract contract ModuleFixtures is
    Test,
    Fixtures,
    Utilities,
    InvariantAsserts
{
    enum ModuleType {
        Community,
        Curated
    }

    struct BatchInfo {
        uint256 nodeOperatorId;
        uint256 count;
    }

    uint256 public constant BOND_SIZE = 2 ether;

    LidoLocatorMock public locator;
    WstETHMock public wstETH;
    LidoMock public stETH;
    BaseModule public module;
    AccountingMock public accounting;
    Stub public feeDistributor;
    ParametersRegistryMock public parametersRegistry;
    ExitPenaltiesMock public exitPenalties;

    address internal actor;
    address internal admin;
    address internal stranger;
    address internal strangerNumberTwo;
    address internal nodeOperator;
    address internal testChargePenaltyRecipient;
    address internal stakingRouter;

    uint32 internal REGULAR_QUEUE;
    uint32 constant PRIORITY_QUEUE = 0;

    struct NodeOperatorSummary {
        uint256 targetLimitMode;
        uint256 targetValidatorsCount;
        uint256 stuckValidatorsCount;
        uint256 refundedValidatorsCount;
        uint256 stuckPenaltyEndTimestamp;
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    struct StakingModuleSummary {
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        _moduleInvariants();
        vm.resumeGasMetering();
    }

    // TODO: Consider ditching the function override and use moduleType instead.
    function _moduleInvariants() internal virtual;

    function moduleType() internal pure virtual returns (ModuleType);

    function createNodeOperator() internal returns (uint256) {
        return createNodeOperator(nodeOperator, 1);
    }

    function createNodeOperator(uint256 keysCount) internal returns (uint256) {
        return createNodeOperator(nodeOperator, keysCount);
    }

    function createNodeOperator(
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        return createNodeOperator(nodeOperator, extendedManagerPermissions);
    }

    function createNodeOperator(
        address managerAddress,
        uint256 keysCount
    ) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        if (keysCount > 0) {
            uploadMoreKeys(nodeOperatorId, keysCount);
        }
    }

    function createNodeOperator(
        address managerAddress,
        uint256 keysCount,
        bytes memory keys,
        bytes memory signatures
    ) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        uploadMoreKeys(nodeOperatorId, keysCount, keys, signatures);
    }

    function createNodeOperator(
        address managerAddress,
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function createNodeOperator(
        address managerAddress,
        address rewardAddress,
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        vm.prank(module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0));
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: managerAddress,
                    rewardAddress: rewardAddress,
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function _toUint248(uint256 value) internal pure returns (uint248) {
        // All penalty/fee figures come from BOND_SIZE (2 ether) so uint248 is ample.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint248(value);
    }

    function uploadMoreKeys(
        uint256 noId,
        uint256 keysCount,
        bytes memory keys,
        bytes memory signatures
    ) internal {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        address managerAddress = module.getNodeOperator(noId).managerAddress;
        vm.deal(managerAddress, amount);
        vm.prank(managerAddress);
        module.addValidatorKeysETH{ value: amount }(
            managerAddress,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function uploadMoreKeys(uint256 noId, uint256 keysCount) internal {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uploadMoreKeys(noId, keysCount, keys, signatures);
    }

    function unvetKeys(uint256 noId, uint256 to) internal {
        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(to)
        );
    }

    function setExited(uint256 noId, uint256 to) internal {
        module.updateExitedValidatorsCount(
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(to)
        );
    }

    function withdrawKey(uint256 noId, uint256 /* keyIndex */) internal {
        WithdrawnValidatorInfo[]
            memory withdrawalsInfo = new WithdrawnValidatorInfo[](1);
        withdrawalsInfo[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        module.reportWithdrawnValidators(withdrawalsInfo);
    }

    function getNodeOperatorSummary(
        uint256 noId
    ) public view returns (NodeOperatorSummary memory) {
        (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getNodeOperatorSummary(noId);
        return
            NodeOperatorSummary({
                targetLimitMode: targetLimitMode,
                targetValidatorsCount: targetValidatorsCount,
                stuckValidatorsCount: stuckValidatorsCount,
                refundedValidatorsCount: refundedValidatorsCount,
                stuckPenaltyEndTimestamp: stuckPenaltyEndTimestamp,
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function getStakingModuleSummary()
        public
        view
        returns (StakingModuleSummary memory)
    {
        (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        return
            StakingModuleSummary({
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function penalize(uint256 noId, uint256 amount) public {
        vm.prank(address(module));
        accounting.penalize(noId, amount);
        module.updateDepositableValidatorsCount(noId);
    }
}

abstract contract ModuleFuzz is ModuleFixtures {
    function testFuzz_CreateNodeOperator(
        uint256 keysCount
    ) public assertInvariants {
        keysCount = bound(keysCount, 1, 99);
        createNodeOperator(keysCount);
        assertEq(module.getNodeOperatorsCount(), 1);
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalAddedKeys, keysCount);
    }

    function testFuzz_CreateMultipleNodeOperators(
        uint256 count
    ) public assertInvariants {
        count = bound(count, 1, 100);
        for (uint256 i = 0; i < count; i++) {
            createNodeOperator(1);
        }
        assertEq(module.getNodeOperatorsCount(), count);
    }

    function testFuzz_UploadKeys(uint256 keysCount) public assertInvariants {
        keysCount = bound(keysCount, 1, 99);
        createNodeOperator(1);
        uploadMoreKeys(0, keysCount);
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalAddedKeys, keysCount + 1);
    }
}

abstract contract ModulePauseTest is ModuleFixtures {
    function test_notPausedByDefault() public view {
        assertFalse(module.isPaused());
    }

    function test_pauseFor() public {
        module.pauseFor(1 days);
        assertTrue(module.isPaused());
        assertEq(module.getResumeSinceTimestamp(), block.timestamp + 1 days);
    }

    function test_pauseFor_indefinitely() public {
        module.pauseFor(type(uint256).max);
        assertTrue(module.isPaused());
        assertEq(module.getResumeSinceTimestamp(), type(uint256).max);
    }

    function test_pauseFor_RevertWhen_ZeroPauseDuration() public {
        vm.expectRevert(PausableUntil.ZeroPauseDuration.selector);
        module.pauseFor(0);
    }

    function test_resume() public {
        module.pauseFor(1 days);
        module.resume();
        assertFalse(module.isPaused());
    }

    function test_auto_resume() public {
        module.pauseFor(1 days);
        assertTrue(module.isPaused());
        vm.warp(block.timestamp + 1 days + 1 seconds);
        assertFalse(module.isPaused());
    }

    function test_pause_RevertWhen_notAdmin() public {
        expectRoleRevert(stranger, module.PAUSE_ROLE());
        vm.prank(stranger);
        module.pauseFor(1 days);
    }

    function test_resume_RevertWhen_notAdmin() public {
        module.pauseFor(1 days);

        expectRoleRevert(stranger, module.RESUME_ROLE());
        vm.prank(stranger);
        module.resume();
    }
}

abstract contract ModulePauseAffectingTest is ModuleFixtures {
    function test_createNodeOperator_RevertWhen_Paused() public {
        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_addValidatorKeysETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function test_addValidatorKeysStETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_addValidatorKeysWstETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }
}

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

abstract contract ModuleAddValidatorKeys is ModuleFixtures {
    function test_AddValidatorKeysWstETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
            if (moduleType() == ModuleType.Community) {
                vm.expectEmit(address(module));
                emit ICSModule.BatchEnqueued(
                    ICSModule(address(module)).QUEUE_LOWEST_PRIORITY(),
                    noId,
                    1
                );
            }
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysWstETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysWstETH_withPermit()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(toWrap);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: wstETHAmount,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
            if (moduleType() == ModuleType.Community) {
                vm.expectEmit(address(module));
                emit ICSModule.BatchEnqueued(
                    ICSModule(address(module)).QUEUE_LOWEST_PRIORITY(),
                    noId,
                    1
                );
            }
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysStETH_withPermit()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        vm.prank(nodeOperator);
        stETH.submit{ value: required }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: required,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
            if (moduleType() == ModuleType.Community) {
                vm.expectEmit(address(module));
                emit ICSModule.BatchEnqueued(
                    ICSModule(address(module)).QUEUE_LOWEST_PRIORITY(),
                    noId,
                    1
                );
            }
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysETH_withMoreEthThanRequired()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        uint256 deposit = required + 1 ether;
        vm.deal(nodeOperator, deposit);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: deposit }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
    }
}

contract GateWithTestCapabilities is Test, Utilities {
    IBaseModule private module;
    IAccounting private accounting;

    WstETHMock private wstETH;
    LidoMock private stETH;

    constructor(IBaseModule _module) {
        module = _module;
        accounting = module.ACCOUNTING();
        ILidoLocator locator = module.LIDO_LOCATOR();
        stETH = LidoMock(locator.lido());
        wstETH = WstETHMock(
            IWithdrawalQueue(locator.withdrawalQueue()).WSTETH()
        );
        stETH.approve(address(wstETH), UINT256_MAX);
    }

    function createNodeOperatorWithKeysWithETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(
            noId,
            keyCount
        );
        vm.deal(address(this), required);

        uint256 nonce = module.getNonce();

        module.addValidatorKeysETH{ value: required }(
            owner,
            noId,
            keyCount,
            keys,
            sigs
        );

        assertEq(module.getNonce(), ++nonce);
    }

    function batchCreateNodeOperatorWithKeysWithETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(
                keys,
                ids[i] - firstId * 48,
                operatorKeyCount * 48
            );
            bytes memory _sigs = slice(
                sigs,
                ids[i] - firstId * 96,
                operatorKeyCount * 96
            );

            uint256 required = accounting.getRequiredBondForNextKeys(
                ids[i],
                operatorKeyCount
            );
            vm.deal(address(this), required);

            module.addValidatorKeysETH{ value: required }(
                owner,
                ids[i],
                operatorKeyCount,
                _keys,
                _sigs
            );

            assertEq(module.getNonce(), ++nonce);
        }
    }

    function createNodeOperatorWithKeysWithStETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(
            noId,
            keyCount
        );
        uint256 toWrap = required + 1 wei;
        vm.deal(address(this), toWrap);
        stETH.submit{ value: toWrap }(address(0));

        uint256 nonce = module.getNonce();

        module.addValidatorKeysStETH(
            owner,
            noId,
            keyCount,
            keys,
            sigs,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(module.getNonce(), ++nonce);
    }

    function batchCreateNodeOperatorWithKeysWithStETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(
                keys,
                ids[i] - firstId * 48,
                operatorKeyCount * 48
            );
            bytes memory _sigs = slice(
                sigs,
                ids[i] - firstId * 96,
                operatorKeyCount * 96
            );

            uint256 required = accounting.getRequiredBondForNextKeys(
                ids[i],
                operatorKeyCount
            );
            uint256 ethAmountToSend = required + 1 wei;
            vm.deal(address(this), ethAmountToSend);
            stETH.submit{ value: ethAmountToSend }(address(0));

            module.addValidatorKeysStETH(
                owner,
                ids[i],
                operatorKeyCount,
                _keys,
                _sigs,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );

            assertEq(module.getNonce(), ++nonce);
        }
    }

    function createNodeOperatorWithKeysWithWstETHBond(
        address owner,
        uint256 keyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256 noId) {
        noId = module.createNodeOperator({
            from: owner,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        uint256 required = accounting.getRequiredBondForNextKeys(
            noId,
            keyCount
        );
        uint256 toWrap = required + 1 wei;
        vm.deal(address(this), toWrap);

        stETH.submit{ value: toWrap }(address(0));
        wstETH.wrap(toWrap);

        module.addValidatorKeysWstETH(
            owner,
            noId,
            keyCount,
            keys,
            sigs,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function batchCreateNodeOperatorWithKeysWithWstETHBond(
        address owner,
        uint256 operatorCount,
        uint256 operatorKeyCount,
        bytes memory keys,
        bytes memory sigs
    ) external returns (uint256[] memory ids) {
        ids = new uint256[](operatorCount);
        for (uint256 i; i < ids.length; i++) {
            ids[i] = module.createNodeOperator(
                owner,
                NodeOperatorManagementProperties({
                    managerAddress: owner,
                    rewardAddress: owner,
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        uint256 firstId = ids[0];
        shuffle(ids);

        uint256 nonce = module.getNonce();

        for (uint256 i; i < ids.length; i++) {
            bytes memory _keys = slice(
                keys,
                ids[i] - firstId * 48,
                operatorKeyCount * 48
            );
            bytes memory _sigs = slice(
                sigs,
                ids[i] - firstId * 96,
                operatorKeyCount * 96
            );

            uint256 required = accounting.getRequiredBondForNextKeys(
                ids[i],
                operatorKeyCount
            );

            uint256 toWrap = required + 1 wei;
            vm.deal(address(this), toWrap);
            stETH.submit{ value: toWrap }(address(0));
            wstETH.wrap(toWrap);

            module.addValidatorKeysWstETH(
                owner,
                ids[i],
                operatorKeyCount,
                _keys,
                _sigs,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );

            assertEq(module.getNonce(), ++nonce);
        }
    }
}

abstract contract ModuleAddValidatorKeysViaGate is ModuleFixtures {
    GateWithTestCapabilities internal gate;

    // Using a modifier to avoid overriding setUp.
    modifier withGate() {
        gate = new GateWithTestCapabilities(module);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(gate));
        _;
    }

    function test_GateAddValidatorKeysETH()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithETHBond(
            nodeOperator,
            keyCount,
            keys,
            sigs
        );
    }

    function test_GateAddValidatorKeysETH_MultipleOperators()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithETHBond(
            nodeOperator,
            operatorCount,
            operatorKeyCount,
            keys,
            sigs
        );
    }

    function test_GateAddValidatorKeysStETH()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithStETHBond(
            nodeOperator,
            keyCount,
            keys,
            sigs
        );
    }

    function test_GateAddValidatorKeysStETH_MultipleOperators()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithStETHBond(
            nodeOperator,
            operatorCount,
            operatorKeyCount,
            keys,
            sigs
        );
    }

    function test_GateAddValidatorKeysWstETH()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 keyCount = 3;
        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.createNodeOperatorWithKeysWithWstETHBond(
            nodeOperator,
            keyCount,
            keys,
            sigs
        );
    }

    function test_AddValidatorKeysWstETH_MultipleOperators()
        public
        assertInvariants
        brutalizeMemory
        withGate
    {
        uint256 operatorCount = 3;
        uint256 operatorKeyCount = 1;
        uint256 keyCount = operatorCount * operatorKeyCount;

        (bytes memory keys, bytes memory sigs) = keysSignatures(keyCount);
        gate.batchCreateNodeOperatorWithKeysWithWstETHBond(
            nodeOperator,
            operatorCount,
            operatorKeyCount,
            keys,
            sigs
        );
    }

    function test_AddValidatorKeysETH_RevertWhenCalledFromAnotherGate()
        public
        assertInvariants
    {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        vm.deal(gateTwo, required);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysETH{ value: required }(
                nodeOperator,
                noId,
                1,
                keys,
                signatures
            );
        }
    }

    function test_AddValidatorKeysStETH_RevertWhenCalledFromAnotherGate()
        public
        assertInvariants
    {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_AddValidatorKeysWstETH_RevertWhenCalledFromAnotherGate()
        public
        assertInvariants
    {
        address gateOne = nextAddress("GATE_ONE");
        address gateTwo = nextAddress("GATE_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), gateTwo);

        vm.prank(gateOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(gateTwo);
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_GateAddValidatorKeysETH_RevertWhenCalledTwice()
        public
        assertInvariants
        withGate
    {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithETHBond(
            nodeOperator,
            1,
            keys,
            sigs
        );

        (keys, sigs) = keysSignatures(1, 1);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysETH(nodeOperator, noId, 1, keys, sigs);
        }
    }

    function test_GateAddValidatorKeysStETH_RevertWhenCalledTwice()
        public
        assertInvariants
        withGate
    {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithStETHBond(
            nodeOperator,
            1,
            keys,
            sigs
        );

        (keys, sigs) = keysSignatures(1, 1);
        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                sigs,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_GateAddValidatorKeysWstETH_RevertWhenCalledTwice()
        public
        assertInvariants
        withGate
    {
        (bytes memory keys, bytes memory sigs) = keysSignatures(1);
        uint256 noId = gate.createNodeOperatorWithKeysWithWstETHBond(
            nodeOperator,
            1,
            keys,
            sigs
        );

        (keys, sigs) = keysSignatures(1, 1);

        {
            vm.expectRevert(IBaseModule.CannotAddKeys.selector);

            vm.prank(address(gate));
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                sigs,
                IAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }
}

abstract contract ModuleAddValidatorKeysNegative is ModuleFixtures {
    function beforeTestSetup(
        bytes4 /* testSelector */
    ) public pure returns (bytes[] memory beforeTestCalldata) {
        beforeTestCalldata = new bytes[](1);
        beforeTestCalldata[0] = abi.encodePacked(this.beforeEach.selector);
    }

    function beforeEach() external {
        createNodeOperator();
    }

    function test_AddValidatorKeysETH_RevertWhen_SenderIsNotEligible() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 0);
        vm.deal(nodeOperator, required);
        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_SenderIsNotEligible()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_InvalidAmount()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required - 1 ether);

        vm.expectRevert(IBaseModule.InvalidAmount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required - 1 ether }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_SenderIsNotEligible()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(IBaseModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }
}

abstract contract ModuleObtainDepositData is ModuleFixtures {
    // TODO: test with near to real values

    function test_obtainDepositData() public assertInvariants {
        uint256 nodeOperatorId = createNodeOperator(1);
        (bytes memory keys, bytes memory signatures) = module
            .getSigningKeysWithSignatures(nodeOperatorId, 0, 1);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(nodeOperatorId, 0);
        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .obtainDepositData(1, "");
        assertEq(obtainedKeys, keys);
        assertEq(obtainedSignatures, signatures);
    }

    function test_obtainDepositData_MultipleOperators()
        public
        assertInvariants
    {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(3);
        uint256 thirdId = createNodeOperator(1);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(firstId, 0);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(secondId, 0);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(thirdId, 0);
        module.obtainDepositData(6, "");
    }

    function test_obtainDepositData_counters() public assertInvariants {
        uint256 keysCount = 1;
        uint256 noId = createNodeOperator(keysCount);
        (bytes memory keys, bytes memory signatures) = module
            .getSigningKeysWithSignatures(noId, 0, keysCount);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositedSigningKeysCountChanged(noId, keysCount);
        (bytes memory depositedKeys, bytes memory depositedSignatures) = module
            .obtainDepositData(keysCount, "");

        assertEq(keys, depositedKeys);
        assertEq(signatures, depositedSignatures);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 0);
        assertEq(no.totalDepositedKeys, 1);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_obtainDepositData_zeroDeposits() public assertInvariants {
        uint256 noId = createNodeOperator();

        (bytes memory publicKeys, bytes memory signatures) = module
            .obtainDepositData(0, "");

        assertEq(publicKeys.length, 0);
        assertEq(signatures.length, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 1);
        assertEq(no.totalDepositedKeys, 0);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_obtainDepositData_unvettedKeys() public assertInvariants {
        createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(1);
        createNodeOperator(3);

        unvetKeys(secondNoId, 0);

        module.obtainDepositData(5, "");

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 5);
        assertEq(depositableValidatorsCount, 0);
    }

    function test_obtainDepositData_counters_WhenLessThanLastBatch()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositedSigningKeysCountChanged(noId, 3);
        module.obtainDepositData(3, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 4);
        assertEq(no.totalDepositedKeys, 3);
        assertEq(no.depositableValidatorsCount, 4);
    }

    function test_obtainDepositData_RevertWhen_NoMoreKeys()
        public
        assertInvariants
    {
        vm.expectRevert(IBaseModule.NotEnoughKeys.selector);
        module.obtainDepositData(1, "");
    }

    function test_obtainDepositData_nonceChanged() public assertInvariants {
        createNodeOperator();
        uint256 nonce = module.getNonce();

        module.obtainDepositData(1, "");
        assertEq(module.getNonce(), nonce + 1);
    }

    function testFuzz_obtainDepositData_MultipleOperators(
        uint256 batchCount,
        uint256 random
    ) public assertInvariants {
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

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);
    }

    function testFuzz_obtainDepositData_OneOperator(
        uint256 batchCount,
        uint256 random
    ) public assertInvariants {
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

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.enqueuedCount, random);
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

abstract contract ModuleVetKeys is ModuleFixtures {
    function test_vetKeys_OnUploadKeys() public assertInvariants {
        uint256 noId = createNodeOperator(2);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 3);
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 3);
    }

    function test_vetKeys_Counters() public assertInvariants {
        uint256 noId = createNodeOperator(false);
        uint256 nonce = module.getNonce();
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_vetKeys_VettedBackViaRemoveKey() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 7);
        unvetKeys({ noId: noId, to: 4 });
        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 4);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 5); // 7 - 2 removed at the next step.

        vm.prank(nodeOperator);
        module.removeKeys(noId, 4, 2); // Remove keys 4 and 5.

        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 5);
    }
}

abstract contract ModuleDecreaseVettedSigningKeysCount is ModuleFixtures {
    function test_decreaseVettedSigningKeysCount_counters()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(noId, 1);
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(noId);
        unvetKeys({ noId: noId, to: 1 });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(module.getNonce(), nonce + 1);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_decreaseVettedSigningKeysCount_MultipleOperators()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 thirdNoId = createNodeOperator(15);
        uint256 newVettedFirst = 5;
        uint256 newVettedSecond = 3;

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(
            firstNoId,
            newVettedFirst
        );
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(firstNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountChanged(
            secondNoId,
            newVettedSecond
        );
        vm.expectEmit(address(module));
        emit IBaseModule.VettedSigningKeysCountDecreased(secondNoId);

        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorPair(firstNoId, secondNoId),
            bytes.concat(
                // Each vetted value mirrors the uint128 field used on-chain, so truncation is safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(newVettedFirst)),
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes16(uint128(newVettedSecond))
            )
        );

        uint256 actualVettedFirst = module
            .getNodeOperator(firstNoId)
            .totalVettedKeys;
        uint256 actualVettedSecond = module
            .getNodeOperator(secondNoId)
            .totalVettedKeys;
        uint256 actualVettedThird = module
            .getNodeOperator(thirdNoId)
            .totalVettedKeys;
        assertEq(actualVettedFirst, newVettedFirst);
        assertEq(actualVettedSecond, newVettedSecond);
        assertEq(actualVettedThird, 15);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_MissingVettedData()
        public
    {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 newVettedFirst = 5;

        vm.expectRevert();
        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorPair(firstNoId, secondNoId),
            _encodeUint128Value(newVettedFirst)
        );
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedEqOld()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 10;

        vm.expectRevert(IBaseModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedGreaterOld()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(IBaseModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedLowerTotalDeposited()
        public
    {
        uint256 noId = createNodeOperator(10);
        module.obtainDepositData(5, "");
        uint256 newVetted = 4;

        vm.expectRevert(IBaseModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        unvetKeys(noId + 1, newVetted);
    }
}

abstract contract ModuleGetSigningKeys is ModuleFixtures {
    function test_getSigningKeys() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });

        assertEq(obtainedKeys, keys, "unexpected keys");
    }

    function test_getSigningKeys_getNonExistingKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
    }

    function test_getSigningKeys_getKeysFromOffset()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory wantedKey = randomBytes(48);
        bytes memory keys = bytes.concat(
            randomBytes(48),
            wantedKey,
            randomBytes(48)
        );

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 1
        });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
    }

    function test_getSigningKeys_WhenNoNodeOperator()
        public
        assertInvariants
        brutalizeMemory
    {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys(0, 0, 1);
    }
}

abstract contract ModuleGetSigningKeysWithSignatures is ModuleFixtures {
    function test_getSigningKeysWithSignatures()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48 * 3);
        bytes memory signatures = randomBytes(96 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .getSigningKeysWithSignatures({
                nodeOperatorId: noId,
                startIndex: 0,
                keysCount: 3
            });

        assertEq(obtainedKeys, keys, "unexpected keys");
        assertEq(obtainedSignatures, signatures, "unexpected signatures");
    }

    function test_getSigningKeysWithSignatures_getNonExistingKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48);
        bytes memory signatures = randomBytes(96);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: signatures
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
    }

    function test_getSigningKeysWithSignatures_getKeysFromOffset()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory wantedKey = randomBytes(48);
        bytes memory wantedSignature = randomBytes(96);
        bytes memory keys = bytes.concat(
            randomBytes(48),
            wantedKey,
            randomBytes(48)
        );
        bytes memory signatures = bytes.concat(
            randomBytes(96),
            wantedSignature,
            randomBytes(96)
        );

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .getSigningKeysWithSignatures({
                nodeOperatorId: noId,
                startIndex: 1,
                keysCount: 1
            });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
        assertEq(
            obtainedSignatures,
            wantedSignature,
            "unexpected sitnature at position 1"
        );
    }

    function test_getSigningKeysWithSignatures_WhenNoNodeOperator()
        public
        assertInvariants
        brutalizeMemory
    {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures(0, 0, 1);
    }
}

abstract contract ModuleRemoveKeys is ModuleFixtures {
    bytes key0 = randomBytes(48);
    bytes key1 = randomBytes(48);
    bytes key2 = randomBytes(48);
    bytes key3 = randomBytes(48);
    bytes key4 = randomBytes(48);

    function test_singleKeyRemoval() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        // at the beginning
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 4);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
        /*
            key4
            key1
            key2
            key3
        */

        // in between
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 1
        });
        /*
            key4
            key3
            key2
        */

        // at the end
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 2,
            keysCount: 1
        });
        /*
            key4
            key3
        */

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });
        assertEq(obtainedKeys, bytes.concat(key4, key3), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 2);
    }

    function test_multipleKeysRemovalFromStart()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key3, key4, key2),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalInBetween()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key0, key3, key4),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalFromEnd()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key4);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key3);

            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 3,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key0, key1, key2),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_removeAllKeys() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: randomBytes(48 * 5),
            signatures: randomBytes(96 * 5)
        });

        {
            vm.expectEmit(address(module));
            emit IBaseModule.TotalSigningKeysCountChanged(noId, 0);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 5
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 0);
    }

    function test_removeKeys_nonceChanged() public assertInvariants {
        bytes memory keys = bytes.concat(key0);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        uint256 nonce = module.getNonce();
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
        assertEq(module.getNonce(), nonce + 1);
    }
}

abstract contract ModuleRemoveKeysChargeFee is ModuleFixtures {
    function test_removeKeys_chargeFee() public assertInvariants {
        uint256 noId = createNodeOperator(3);

        uint256 amountToCharge = module
            .PARAMETERS_REGISTRY()
            .getKeyRemovalCharge(0) * 2;

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                amountToCharge
            ),
            1
        );

        vm.expectEmit(address(module));
        emit IBaseModule.KeyRemovalChargeApplied(noId);

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the charge is fully paid.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_removeKeys_chargeFeeMoreThanBond() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        vm.prank(admin);
        module.PARAMETERS_REGISTRY().setKeyRemovalCharge(
            0,
            BOND_SIZE + 1 ether
        );

        vm.prank(nodeOperator);
        module.removeKeys(noId, 0, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 0);
        // Target limit should be set to 0 and mode to 2 if the charge is more than bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_removeKeys_withNoFee() public assertInvariants {
        vm.prank(admin);
        module.PARAMETERS_REGISTRY().setKeyRemovalCharge(0, 0);

        uint256 noId = createNodeOperator(3);

        vm.recordLogs();

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertNotEq(
                entries[i].topics[0],
                IBaseModule.KeyRemovalChargeApplied.selector
            );
        }

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the is no charge.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }
}

abstract contract ModuleRemoveKeysReverts is ModuleFixtures {
    function test_removeKeys_RevertWhen_NoNodeOperator()
        public
        assertInvariants
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.removeKeys({ nodeOperatorId: 0, startIndex: 0, keysCount: 1 });
    }

    function test_removeKeys_RevertWhen_MoreThanAdded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });
    }

    function test_removeKeys_RevertWhen_LessThanDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 2
        });

        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
    }

    function test_removeKeys_RevertWhen_NotEligible() public assertInvariants {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.prank(stranger);
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
    }

    function test_removeKeys_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 0
        });
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

        module.reportWithdrawnValidators(validatorInfos);
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

abstract contract ModuleUpdateTargetValidatorsLimits is ModuleFixtures {
    function test_updateTargetValidatorsLimits() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_updateTargetValidatorsLimits_sameValues()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1);
        assertEq(summary.targetValidatorsCount, 1);
    }

    function test_updateTargetValidatorsLimits_limitIsZero()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 0);
        module.updateTargetValidatorsLimits(noId, 1, 0);
    }

    function test_updateTargetValidatorsLimits_FromDisabledToDisabled_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.targetLimit, 0);
    }

    function test_updateTargetValidatorsLimits_enableSoftLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 10);
        module.updateTargetValidatorsLimits(noId, 1, 10);
    }

    function test_updateTargetValidatorsLimits_enableHardLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 2, 10);
        module.updateTargetValidatorsLimits(noId, 2, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_switchFromHardToSoftLimit()
        public
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 1, 5);
        module.updateTargetValidatorsLimits(noId, 1, 5);
    }

    function test_updateTargetValidatorsLimits_switchFromSoftToHardLimit()
        public
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit IBaseModule.TargetValidatorsCountChanged(noId, 2, 5);
        module.updateTargetValidatorsLimits(noId, 2, 5);
    }

    function test_updateTargetValidatorsLimits_NoUnvetKeysWhenLimitDisabled()
        public
    {
        uint256 noId = createNodeOperator(2);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 0, 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 2);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.updateTargetValidatorsLimits(0, 1, 1);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitExceedsUint32()
        public
    {
        createNodeOperator(1);
        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(
            0,
            1,
            uint256(type(uint32).max) + 1
        );
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitModeExceedsMax()
        public
    {
        createNodeOperator(1);
        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(0, 3, 1);
    }
}

abstract contract ModuleUpdateExitedValidatorsCount is ModuleFixtures {
    function test_updateExitedValidatorsCount_NonZero()
        public
        assertInvariants
    {
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

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_updateExitedValidatorsCount_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
    }

    function test_updateExitedValidatorsCount_RevertWhen_CountMoreThanDeposited()
        public
    {
        createNodeOperator(1);

        vm.expectRevert(
            IBaseModule.ExitedKeysHigherThanTotalDeposited.selector
        );
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
    }

    function test_updateExitedValidatorsCount_RevertWhen_ExitedKeysDecrease()
        public
    {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.expectRevert(IBaseModule.ExitedKeysDecrease.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000000))
        );
    }

    function test_updateExitedValidatorsCount_NoEventIfSameValue()
        public
        assertInvariants
    {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.recordLogs();
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // One event is NonceChanged
        assertEq(logs.length, 1);
    }
}

abstract contract ModuleUnsafeUpdateValidatorsCount is ModuleFixtures {
    function test_unsafeUpdateValidatorsCount_NonZero()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(5);
        module.obtainDepositData(5, "");
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 1);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 1, "totalExitedKeys not increased");
        assertEq(
            no.stuckValidatorsCount,
            0,
            "stuckValidatorsCount not increased"
        );

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: 100500,
            exitedValidatorsKeysCount: 1
        });
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_NotStakingRouter()
        public
    {
        expectRoleRevert(stranger, module.STAKING_ROUTER_ROLE());
        vm.prank(stranger);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: 100500,
            exitedValidatorsKeysCount: 1
        });
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_ExitedCountMoreThanDeposited()
        public
    {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(
            IBaseModule.ExitedKeysHigherThanTotalDeposited.selector
        );
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 100500
        });
    }

    function test_unsafeUpdateValidatorsCount_DecreaseExitedKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        setExited(0, 1);

        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 0
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 0, "totalExitedKeys should be zero");
    }

    function test_unsafeUpdateValidatorsCount_NoEventIfSameValue()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });

        vm.recordLogs();
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // One event is NonceChanged
        assertEq(logs.length, 1);
    }
}

abstract contract ModuleReportGeneralDelayedPenalty is ModuleFixtures {
    function test_reportGeneralDelayedPenalty_HappyPath()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getGeneralDelayedPenaltyAdditionalFine(0);

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltyReported(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            fine,
            "Test penalty"
        );
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            BOND_SIZE /
                2 +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportGeneralDelayedPenalty(
            0,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_ZeroAmountAndZeroAdditionalFine()
        public
    {
        uint256 noId = createNodeOperator();
        module.PARAMETERS_REGISTRY().setGeneralDelayedPenaltyAdditionalFine(
            0,
            0
        );
        vm.expectRevert(IBaseModule.InvalidAmount.selector);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            0 ether,
            "Test penalty"
        );
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_ZeroPenaltyType()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(IGeneralPenalty.ZeroPenaltyType.selector);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(0),
            0 ether,
            "Test penalty"
        );
    }

    function test_reportGeneralDelayedPenalty_NoNonceChange()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        vm.deal(nodeOperator, 32 ether);
        vm.prank(nodeOperator);
        accounting.depositETH{ value: 32 ether }(0);

        uint256 nonce = module.getNonce();

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        assertEq(module.getNonce(), nonce);
    }

    function test_reportGeneralDelayedPenalty_UpdateDepositableAfterUnlock()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            BOND_SIZE /
                2 +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);

        createNodeOperator();
        module.obtainDepositData(1, "");

        vm.warp(accounting.getBondLockPeriod() + 1);

        if (moduleType() == ModuleType.Community) {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(
                ICSModule(address(module)).QUEUE_LOWEST_PRIORITY(),
                noId,
                1
            );
        }
        module.updateDepositableValidatorsCount(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);
    }
}

abstract contract ModuleCancelGeneralDelayedPenalty is ModuleFixtures {
    function test_cancelGeneralDelayedPenalty_HappyPath()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltyCancelled(
            noId,
            BOND_SIZE /
                2 +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
        module.cancelGeneralDelayedPenalty(
            noId,
            BOND_SIZE /
                2 +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(lockedBond, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_cancelGeneralDelayedPenalty_Partial()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            "Test penalty"
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltyCancelled(
            noId,
            BOND_SIZE / 2
        );
        module.cancelGeneralDelayedPenalty(noId, BOND_SIZE / 2);

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(
                0
            )
        );
        // nonce should not change due to no changes in the depositable validators
        assertEq(module.getNonce(), nonce);
    }

    function test_cancelGeneralDelayedPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.cancelGeneralDelayedPenalty(0, 1 ether);
    }
}

abstract contract ModuleSettleGeneralDelayedPenaltyBasic is ModuleFixtures {
    function test_settleGeneralDelayedPenalty() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(noId);
        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        // If the penalty is settled the targetValidatorsCount should be 0
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_settleGeneralDelayedPenalty_revertWhen_InvalidInput()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.settleGeneralDelayedPenalty(idsToSettle, new uint256[](0));
    }

    function test_settleGeneralDelayedPenalty_lockedGreaterThanAllowedToSettle()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary
            .depositableValidatorsCount;

        module.settleGeneralDelayedPenalty(idsToSettle, UintArr(amount));
        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(
            lock.amount,
            amount +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleGeneralDelayedPenalty_multipleNOs()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        module.reportGeneralDelayedPenalty(
            firstNoId,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );
        module.reportGeneralDelayedPenalty(
            secondNoId,
            bytes32(abi.encode(1)),
            BOND_SIZE,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(firstNoId);
        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(secondNoId);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        lock = accounting.getLockedBondInfo(secondNoId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneWithLockedGreaterThanAllowedToSettle()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](2);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        uint256 amount = 1 ether;
        module.reportGeneralDelayedPenalty(
            firstNoId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );
        module.reportGeneralDelayedPenalty(
            secondNoId,
            bytes32(abi.encode(1)),
            BOND_SIZE,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(secondNoId);
        module.settleGeneralDelayedPenalty(
            idsToSettle,
            UintArr(amount, type(uint256).max)
        );

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(
            lock.amount,
            amount +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        lock = accounting.getLockedBondInfo(secondNoId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_NoLock() public assertInvariants {
        uint256 noId = createNodeOperator();
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary
            .depositableValidatorsCount;
        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_NoLock()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneWithNoLock()
        public
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.reportGeneralDelayedPenalty(
            secondNoId,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(secondNoId);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_withDuplicates() public {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](3);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        idsToSettle[2] = secondNoId;

        uint256 bondBalanceBefore = accounting.getBond(secondNoId);

        uint256 lockAmount = 1 ether;
        module.reportGeneralDelayedPenalty(
            secondNoId,
            bytes32(abi.encode(1)),
            lockAmount,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(secondNoId);
        module.settleGeneralDelayedPenalty(
            idsToSettle,
            UintArr(type(uint256).max, type(uint256).max, type(uint256).max)
        );

        uint256 bondBalanceAfter = accounting.getBond(secondNoId);

        BondLock.BondLockData memory currentLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(currentLock.amount, 0 ether);
        assertEq(currentLock.until, 0);
        assertEq(
            bondBalanceAfter,
            bondBalanceBefore -
                lockAmount -
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(0)
        );
    }

    function test_settleGeneralDelayedPenalty_RevertWhen_NoExistingNodeOperator()
        public
    {
        uint256 noId = createNodeOperator();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.settleGeneralDelayedPenalty(
            UintArr(noId + 1),
            UintArr(type(uint256).max)
        );
    }
}

abstract contract ModuleSettleGeneralDelayedPenaltyAdvanced is ModuleFixtures {
    function test_settleGeneralDelayedPenalty_PeriodIsExpired() public {
        uint256 noId = createNodeOperator();
        uint256 period = accounting.getBondLockPeriod();
        uint256 amount = 1 ether;

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        vm.warp(block.timestamp + period + 1 seconds);

        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        assertEq(accounting.getActualLockedBond(noId), 0);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneExpired() public {
        uint256 period = accounting.getBondLockPeriod();
        uint256 firstNoId = createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(2);
        module.reportGeneralDelayedPenalty(
            firstNoId,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );
        vm.warp(block.timestamp + period + 1 seconds);
        module.reportGeneralDelayedPenalty(
            secondNoId,
            bytes32(abi.encode(1)),
            BOND_SIZE,
            "Test penalty"
        );

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(secondNoId);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        assertEq(accounting.getActualLockedBond(firstNoId), 0);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_NoBond() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = accounting.getBond(noId) + 1 ether;

        // penalize all current bond to make an edge case when there is no bond but a new lock is applied
        penalize(noId, amount);

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );
        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(noId);
        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }
}

abstract contract ModuleCompensateGeneralDelayedPenalty is ModuleFixtures {
    function test_compensateGeneralDelayedPenalty() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltyCompensated(
            noId,
            amount + fine
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.compensateLockedBondETH.selector,
                noId
            )
        );
        vm.deal(nodeOperator, amount + fine);
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty{ value: amount + fine }(noId);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_compensateGeneralDelayedPenalty_Partial()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IGeneralPenalty.GeneralDelayedPenaltyCompensated(noId, amount);

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.compensateLockedBondETH.selector,
                noId
            )
        );
        vm.deal(nodeOperator, amount);
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty{ value: amount }(noId);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, fine);
        assertEq(module.getNonce(), nonce);
    }

    function test_compensateGeneralDelayedPenalty_depositableValidatorsChanged()
        public
    {
        uint256 noId = createNodeOperator(2);
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );
        module.obtainDepositData(1, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        vm.deal(nodeOperator, amount + fine);
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty{ value: amount + fine }(noId);
        uint256 depositableAfter = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;
        assertEq(depositableAfter, depositableBefore + 1);
    }

    function test_compensateGeneralDelayedPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.compensateGeneralDelayedPenalty{ value: 1 ether }(0);
    }

    function test_compensateGeneralDelayedPenalty_RevertWhen_NotManager()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        module.compensateGeneralDelayedPenalty{ value: 1 ether }(noId);
    }
}

abstract contract ModuleReportWithdrawnValidators is ModuleFixtures {
    function test_reportWithdrawnValidators_NoPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(
            noId,
            keyIndex,
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            0,
            pubkey
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        bool withdrawn = module.isValidatorWithdrawn(noId, keyIndex);
        assertTrue(withdrawn);

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportWithdrawnValidators_changeNonce()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(
            noId,
            keyIndex,
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE - balanceShortage,
            0,
            pubkey
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        // depositable decrease should
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportWithdrawnValidators_lowExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_superLowExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE + 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_exitDelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_hugeExitDelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_exitDelayFeeWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 fee = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1 ether -
                1 wei,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                fee * multiplier
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_exitDelayFeeAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 fee = (1 << 245) - 1;
        uint256 multiplier = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE /
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                fee * multiplier
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_strikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_hugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_strikesPenaltyWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1 ether -
                1 wei,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_strikesPenaltyAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 penalty = (1 << 245) - 1;
        uint256 multiplier = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE /
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_slashingPenaltyApplied()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_slashingPenaltyOverridesExitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                11 ether,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_slashingPenaltyNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 7 ether;
        uint256 multiplier = 5;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_slashingPenalty_RevertWhenNotReported()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectRevert(
            IBaseModule.SlashingPenaltyIsNotApplicable.selector,
            address(module)
        );

        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_DelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = 0.7 ether;
        uint256 withdrawalRequestFeeAmount = 0.3 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_hugeDelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are covered by the bond but the penalties are not.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeHugeWithdrawalFee_DelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE -
            strikesPenaltyAmount -
            0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_HugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are covered by the bond but the penalties are not.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeHugeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_DelayAndStrikesPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = 0.17 ether;
        uint256 strikesPenaltyAmount = 0.31 ether;
        uint256 withdrawalRequestFeeAmount = 0.42 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_DelayAndStrikesPenalties_AllHuge()
        public
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE + 17 ether;
        uint256 strikesPenaltyAmount = BOND_SIZE + 31 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 42 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFee_zeroPenaltyValue()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_chargeHugeWithdrawalFee_zeroPenaltyValue()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportWithdrawnValidators_chargeWithdrawalFeeNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 withdrawalRequestFee = 0.1 ether;
        uint256 multiplier = 5;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(withdrawalRequestFee, true)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFee
            )
        );
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_dontChargeWithdrawalFee_noPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if there were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_dontChargeWithdrawalFee_exitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;
        uint256 balanceShortage = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportWithdrawnValidators_unbondedKeys()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportWithdrawnValidators(validatorInfos);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportWithdrawnValidators_RevertWhen_ZeroExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 0,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectRevert(IBaseModule.ZeroExitBalance.selector);
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_RevertWhen_NoNodeOperator()
        public
        assertInvariants
    {
        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: 32 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_RevertWhen_InvalidKeyIndexOffset()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 32 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidators_alreadyWithdrawn()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportWithdrawnValidators(validatorInfos);

        uint256 nonceBefore = module.getNonce();
        module.reportWithdrawnValidators(validatorInfos);
        assertEq(
            module.getNonce(),
            nonceBefore,
            "Nonce should not change when trying to withdraw already withdrawn key"
        );
    }

    function test_reportWithdrawnValidators_nonceIncrementsOnceForManyWithdrawals()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](3);
        for (uint256 i = 0; i < 3; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0,
                isSlashed: false
            });
        }
        module.reportWithdrawnValidators(validatorInfos);
        assertEq(
            module.getNonce(),
            nonceBefore + 1,
            "Module nonce should increment only once for batch withdrawals"
        );
    }

    function test_onValidatorSlashed_HappyPath() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorSlashingReported(noId, keyIndex, pubkey);

        module.onValidatorSlashed(noId, keyIndex);
        assertTrue(module.isValidatorSlashed(noId, keyIndex));
    }

    function test_onValidatorSlashed_RevertWhen_CalledTwice() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;

        module.onValidatorSlashed(noId, keyIndex);
        vm.expectRevert(
            IBaseModule.ValidatorSlashingAlreadyReported.selector,
            address(module)
        );
        module.onValidatorSlashed(noId, keyIndex);
    }

    function test_onValidatorSlashed_RevertWhen_OperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.onValidatorSlashed(0, 0);
    }

    function test_onValidatorSlashed_RevertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.onValidatorSlashed(noId, 0);
    }
}

abstract contract ModuleGetStakingModuleSummary is ModuleFixtures {
    function test_getStakingModuleSummary_depositableValidators()
        public
        assertInvariants
    {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(2);
        StakingModuleSummary memory summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.depositableValidatorsCount, 1);
        assertEq(secondNo.depositableValidatorsCount, 2);
        assertEq(summary.depositableValidatorsCount, 3);
    }

    function test_getStakingModuleSummary_depositedValidators()
        public
        assertInvariants
    {
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

    function test_getStakingModuleSummary_exitedValidators()
        public
        assertInvariants
    {
        uint256 first = createNodeOperator(2);
        uint256 second = createNodeOperator(2);
        module.obtainDepositData(4, "");
        StakingModuleSummary memory summary = getStakingModuleSummary();
        assertEq(summary.totalExitedValidators, 0);

        module.updateExitedValidatorsCount(
            bytes.concat(
                bytes8(0x0000000000000000),
                bytes8(0x0000000000000001)
            ),
            bytes.concat(
                bytes16(0x00000000000000000000000000000001),
                bytes16(0x00000000000000000000000000000002)
            )
        );

        summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.totalExitedKeys, 1);
        assertEq(secondNo.totalExitedKeys, 2);
        assertEq(summary.totalExitedValidators, 3);
    }
}

contract MyModule is BaseModule {
    error NotImplementedInTest();

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    )
        BaseModule(
            moduleType,
            lidoLocator,
            parametersRegistry,
            accounting,
            exitPenalties
        )
    {
        _disableInitializers();
    }

    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata depositCalldata
    )
        external
        virtual
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        revert NotImplementedInTest();
    }

    function _onOperatorDepositableChange(
        uint256 nodeOperatorId
    ) internal override {
        revert NotImplementedInTest();
    }

    function onWithdrawalCredentialsChanged() external {
        revert NotImplementedInTest();
    }
}

abstract contract ModuleAccessControl is ModuleFixtures {
    function test_adminRole() public {
        MyModule csm = new MyModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        _enableInitializers(address(csm));
        csm.initialize(actor);

        bytes32 role = csm.DEFAULT_ADMIN_ROLE();
        vm.prank(actor);
        csm.grantRole(role, stranger);
        assertTrue(csm.hasRole(role, stranger));

        vm.prank(actor);
        csm.revokeRole(role, stranger);
        assertFalse(csm.hasRole(role, stranger));
    }

    function test_adminRole_revert() public {
        MyModule csm = new MyModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        bytes32 role = csm.DEFAULT_ADMIN_ROLE();
        bytes32 adminRole = csm.DEFAULT_ADMIN_ROLE();

        vm.startPrank(stranger);
        expectRoleRevert(stranger, adminRole);
        csm.grantRole(role, stranger);
    }

    function test_createNodeOperatorRole() public {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_createNodeOperatorRole_revert() public {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_reportGeneralDelayedPenaltyRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_GENERAL_DELAYED_PENALTY_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );
    }

    function test_reportGeneralDelayedPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_GENERAL_DELAYED_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            1 ether,
            "Test penalty"
        );
    }

    function test_settleGeneralDelayedPenaltyRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }

    function test_settleGeneralDelayedPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.settleGeneralDelayedPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }

    function test_verifierRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.VERIFIER_ROLE();

        vm.startPrank(admin);
        module.grantRole(role, actor);
        module.grantRole(module.STAKING_ROUTER_ROLE(), admin);
        module.obtainDepositData(1, "");
        vm.stopPrank();

        vm.prank(actor);
        module.onValidatorSlashed(noId, 0);
    }

    function test_verifierRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.VERIFIER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.onValidatorSlashed(noId, 0);
    }

    function test_reportWithdrawnValidatorsRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SUBMIT_WITHDRAWALS_ROLE();

        vm.startPrank(admin);
        module.grantRole(role, actor);
        module.grantRole(module.STAKING_ROUTER_ROLE(), admin);
        module.obtainDepositData(1, "");
        vm.stopPrank();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.prank(actor);
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_reportWithdrawnValidatorsRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SUBMIT_WITHDRAWALS_ROLE();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportWithdrawnValidators(validatorInfos);
    }

    function test_recovererRole() public {
        bytes32 role = module.RECOVERER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.recoverEther();
    }

    function test_recovererRole_revert() public {
        bytes32 role = module.RECOVERER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.recoverEther();
    }
}

abstract contract ModuleStakingRouterAccessControl is ModuleFixtures {
    function test_stakingRouterRole_onRewardsMinted() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onRewardsMinted(0);
    }

    function test_stakingRouterRole_onRewardsMinted_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.onRewardsMinted(0);
    }

    function test_stakingRouterRole_updateExitedValidatorsCount() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.updateExitedValidatorsCount("", "");
    }

    function test_stakingRouterRole_updateExitedValidatorsCount_revert()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.updateExitedValidatorsCount("", "");
    }

    function test_stakingRouterRole_updateTargetValidatorsLimits() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_stakingRouterRole_updateTargetValidatorsLimits_revert()
        public
    {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_stakingRouterRole_onExitedAndStuckValidatorsCountsUpdated()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onExitedAndStuckValidatorsCountsUpdated();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_noDepositable()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_withDepositable()
        public
    {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        if (moduleType() == ModuleType.Community) {
            vm.expectRevert(
                ICSModule
                    .DepositQueueHasUnsupportedWithdrawalCredentials
                    .selector
            );
        } else {
            vm.expectRevert(); // TODO: Fill in the correct error for the CuratedModule.
        }
        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_RoleRevert()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_unsafeUpdateValidatorsCountRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.unsafeUpdateValidatorsCount(noId, 0);
    }

    function test_stakingRouterRole_unsafeUpdateValidatorsCountRole_revert()
        public
    {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.unsafeUpdateValidatorsCount(noId, 0);
    }

    function test_stakingRouterRole_unvetKeys() public {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.decreaseVettedSigningKeysCount(new bytes(0), new bytes(0));
    }

    function test_stakingRouterRole_unvetKeys_revert() public {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.decreaseVettedSigningKeysCount(new bytes(0), new bytes(0));
    }
}

abstract contract ModuleDepositableValidatorsCount is ModuleFixtures {
    function test_depositableValidatorsCountChanges_OnDeposit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 7);
        module.obtainDepositData(3, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 4);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 4);
    }

    function test_depositableValidatorsCountChanges_OnUnsafeUpdateExitedValidators()
        public
    {
        uint256 noId = createNodeOperator(7);
        createNodeOperator(2);
        module.obtainDepositData(4, "");

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
    }

    function test_depositableValidatorsCountDoesntChange_OnUnsafeUpdateStuckValidators()
        public
    {
        uint256 noId = createNodeOperator(7);
        createNodeOperator(2);
        module.obtainDepositData(4, "");

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 0
        });
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
    }

    function test_depositableValidatorsCountChanges_OnUnvetKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 nonce = module.getNonce();
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        unvetKeys(noId, 3);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_depositableValidatorsCountChanges_OnWithdrawal()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);

        penalize(noId, BOND_SIZE * 3);

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](3);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        validatorInfos[1] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 1,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        validatorInfos[2] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 2,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                BOND_SIZE,
            slashingPenalty: 0,
            isSlashed: false
        }); // Large CL balance drop, that doesn't change the unbonded count.

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 0);
        module.reportWithdrawnValidators(validatorInfos);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 2);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 2);
    }

    function test_depositableValidatorsCountChanges_OnReportGeneralDelayedPenalty()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            (BOND_SIZE * 3) / 2,
            "Test penalty"
        ); // Lock bond to unbond 2 validators.
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 1);
    }

    function test_depositableValidatorsCountChanges_OnReleaseGeneralDelayedPenalty()
        public
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE,
            "Test penalty"
        ); // Lock bond to unbond 2 validators (there's additional fine).
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        module.cancelGeneralDelayedPenalty(
            noId,
            accounting.getLockedBondInfo(noId).amount
        );
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
    }

    function test_depositableValidatorsCountChanges_OnRemoveUnvetted()
        public
        assertInvariants
    {
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

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys"
        );

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

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedDepositedOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
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

    function test_partiallyUnbondedDepositedOnly_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
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

    function test_partiallyUnbondedDepositableOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedDepositableOnly_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }
}

abstract contract ModuleOnRewardsMinted is ModuleFixtures {
    function test_onRewardsMinted() public assertInvariants {
        uint256 reportShares = 100000;
        uint256 someDustShares = 100;

        stETH.mintShares(address(module), someDustShares);
        stETH.mintShares(address(module), reportShares);

        vm.prank(stakingRouter);
        module.onRewardsMinted(reportShares);

        assertEq(stETH.sharesOf(address(module)), someDustShares);
        assertEq(stETH.sharesOf(address(feeDistributor)), reportShares);
    }
}

abstract contract ModuleRecoverERC20 is ModuleFixtures {
    function test_recoverERC20() public assertInvariants {
        vm.startPrank(admin);
        module.grantRole(module.RECOVERER_ROLE(), stranger);
        vm.stopPrank();

        ERC20Testable token = new ERC20Testable();
        token.mint(address(module), 1000);

        vm.prank(stranger);
        vm.expectEmit(address(module));
        emit IAssetRecovererLib.ERC20Recovered(address(token), stranger, 1000);
        module.recoverERC20(address(token), 1000);

        assertEq(token.balanceOf(address(module)), 0);
        assertEq(token.balanceOf(stranger), 1000);
    }
}

abstract contract ModuleSupportsInterface is ModuleFixtures {
    function test_supportsInterface_ReturnsTrueForINodeOperatorOwner()
        public
        view
    {
        assertTrue(
            module.supportsInterface(type(INodeOperatorOwner).interfaceId)
        );
    }

    function test_supportsInterface_ReturnsFalseForUnknownInterface()
        public
        view
    {
        assertFalse(module.supportsInterface(bytes4(uint32(0xdeadbeef))));
    }
}

abstract contract ModuleMisc is ModuleFixtures {
    function test_getInitializedVersion() public view {
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_getActiveNodeOperatorsCount_OneOperator()
        public
        assertInvariants
    {
        createNodeOperator();
        uint256 noCount = module.getNodeOperatorsCount();
        assertEq(noCount, 1);
    }

    function test_getActiveNodeOperatorsCount_MultipleOperators()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();
        uint256 noCount = module.getNodeOperatorsCount();
        assertEq(noCount, 3);
    }

    function test_getNodeOperatorIsActive() public assertInvariants {
        uint256 noId = createNodeOperator();
        bool active = module.getNodeOperatorIsActive(noId);
        assertTrue(active);
    }

    function test_getNodeOperatorIds() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();

        uint256[] memory noIds = new uint256[](3);
        noIds[0] = firstNoId;
        noIds[1] = secondNoId;
        noIds[2] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(0, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_Offset() public assertInvariants {
        createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = secondNoId;
        noIds[1] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(1, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_OffsetEqualsNodeOperatorsCount()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(3, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_OffsetHigherThanNodeOperatorsCount()
        public
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(4, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_ZeroLimit() public assertInvariants {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](0);
        noIdsActual = module.getNodeOperatorIds(0, 0);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_ZeroLimitAndOffsetHigherThanNodeOperatorsCount()
        public
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](0);
        noIdsActual = module.getNodeOperatorIds(4, 0);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_Limit() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = firstNoId;
        noIds[1] = secondNoId;

        uint256[] memory noIdsActual = new uint256[](2);
        noIdsActual = module.getNodeOperatorIds(0, 2);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_LimitAndOffset() public assertInvariants {
        createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = secondNoId;
        noIds[1] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(1, 2);

        assertEq(noIdsActual, noIds);
    }

    function test_getActiveNodeOperatorsCount_One() public assertInvariants {
        createNodeOperator();

        uint256 activeCount = module.getActiveNodeOperatorsCount();

        assertEq(activeCount, 1);
    }

    function test_getActiveNodeOperatorsCount_Multiple()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256 activeCount = module.getActiveNodeOperatorsCount();

        assertEq(activeCount, 3);
    }

    function test_getNodeOperatorTotalDepositedKeys() public assertInvariants {
        uint256 noId = createNodeOperator();

        uint256 depositedCount = module.getNodeOperatorTotalDepositedKeys(noId);
        assertEq(depositedCount, 0);

        module.obtainDepositData(1, "");

        depositedCount = module.getNodeOperatorTotalDepositedKeys(noId);
        assertEq(depositedCount, 1);
    }

    function test_getNodeOperatorManagementProperties()
        public
        assertInvariants
    {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = true;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        NodeOperatorManagementProperties memory props = module
            .getNodeOperatorManagementProperties(noId);
        assertEq(props.managerAddress, manager);
        assertEq(props.rewardAddress, reward);
        assertEq(props.extendedManagerPermissions, extended);
    }

    function test_getNodeOperatorOwner() public assertInvariants {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = false;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        assertEq(module.getNodeOperatorOwner(noId), reward);
    }

    function test_getNodeOperatorOwner_ExtendedPermissions()
        public
        assertInvariants
    {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = true;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        assertEq(module.getNodeOperatorOwner(noId), manager);
    }
}

abstract contract ModuleExitDeadlineThreshold is ModuleFixtures {
    function test_exitDeadlineThreshold() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        assertEq(exitDeadlineThreshold, parametersRegistry.allowedExitDelay());
    }

    function test_exitDeadlineThreshold_RevertWhenNoNodeOperator()
        public
        assertInvariants
    {
        uint256 noId = 0;
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.exitDeadlineThreshold(noId);
    }
}

abstract contract ModuleIsValidatorExitDelayPenaltyApplicable is
    ModuleFixtures
{
    function test_isValidatorExitDelayPenaltyApplicable_notApplicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(false);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable);
    }

    function test_isValidatorExitDelayPenaltyApplicable_applicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(true);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
        assertTrue(applicable);
    }
}

abstract contract ModuleReportValidatorExitDelay is ModuleFixtures {
    function test_reportValidatorExitDelay() public {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.processExitDelayReport.selector,
                noId,
                publicKey,
                exitDeadlineThreshold
            )
        );
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDeadlineThreshold
        );
    }

    function test_reportValidatorExitDelay_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 exitDelay = parametersRegistry.allowedExitDelay();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDelay
        );
    }
}

abstract contract ModuleOnValidatorExitTriggered is ModuleFixtures {
    function test_onValidatorExitTriggered() public assertInvariants {
        uint256 noId = createNodeOperator();
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.processTriggeredExit.selector,
                noId,
                publicKey,
                paidFee,
                exitType
            )
        );
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
    }

    function test_onValidatorExitTriggered_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
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
