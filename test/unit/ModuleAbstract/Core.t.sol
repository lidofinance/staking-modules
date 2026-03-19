// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BaseModule } from "src/abstract/BaseModule.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ERC20Testable } from "../../helpers/ERCTestable.sol";
import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleFuzz is ModuleFixtures {
    function testFuzz_CreateNodeOperator(uint256 keysCount) public assertInvariants {
        keysCount = bound(keysCount, 1, 99);
        createNodeOperator(keysCount);
        assertEq(module.getNodeOperatorsCount(), 1);
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalAddedKeys, keysCount);
    }

    function testFuzz_CreateMultipleNodeOperators(uint256 count) public assertInvariants {
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
        module.addValidatorKeysETH(nodeOperator, noId, keysCount, keys, signatures);
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

contract MyModule is BaseModule {
    error NotImplementedInTest();

    uint64 internal constant INITIALIZED_VERSION = 1;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    ) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties) {
        _disableInitializers();
    }

    function initialize(address admin) external reinitializer(INITIALIZED_VERSION) {
        __BaseModule_init(admin);
    }

    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata depositCalldata
    ) external virtual returns (bytes memory publicKeys, bytes memory signatures) {
        revert NotImplementedInTest();
    }

    function allocateDeposits(
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory allocations) {
        maxDepositAmount;
        pubkeys;
        keyIndices;
        operatorIds;
        topUpLimits;
        revert NotImplementedInTest();
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal override returns (bool) {
        nodeOperatorId;
        newCount;
        incrementNonceIfUpdated;
        revert NotImplementedInTest();
    }

    function getStakingModuleSummary()
        external
        view
        override
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        revert NotImplementedInTest();
    }

    function helper_grantRole(bytes32 role, address who) external {
        _grantRole(role, who);
    }
}

abstract contract ModuleAccessControl is ModuleFixtures {
    function test_adminRole() public {
        MyModule module = new MyModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        module.helper_grantRole(module.DEFAULT_ADMIN_ROLE(), admin);
        bytes32 role = module.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        module.grantRole(role, stranger);
        assertTrue(module.hasRole(role, stranger));

        vm.prank(admin);
        module.revokeRole(role, stranger);
        assertFalse(module.hasRole(role, stranger));
    }

    function test_adminRole_revert() public {
        MyModule module = new MyModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        module.helper_grantRole(module.DEFAULT_ADMIN_ROLE(), admin);

        bytes32 adminRole = module.DEFAULT_ADMIN_ROLE();
        bytes32 role = module.DEFAULT_ADMIN_ROLE();

        vm.startPrank(stranger);
        expectRoleRevert(stranger, adminRole);
        module.grantRole(role, stranger);
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
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), 1 ether, "Test penalty");
    }

    function test_reportGeneralDelayedPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_GENERAL_DELAYED_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), 1 ether, "Test penalty");
    }

    function test_settleGeneralDelayedPenaltyRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));
    }

    function test_settleGeneralDelayedPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));
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
        module.reportValidatorSlashing(noId, 0);
    }

    function test_verifierRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.VERIFIER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportValidatorSlashing(noId, 0);
    }

    function test_reportRegularWithdrawnValidatorsRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE();

        vm.startPrank(admin);
        module.grantRole(role, actor);
        module.grantRole(module.STAKING_ROUTER_ROLE(), admin);
        module.obtainDepositData(1, "");
        vm.stopPrank();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.prank(actor);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidatorsRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidatorsRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE();

        vm.startPrank(admin);
        module.grantRole(role, actor);
        module.grantRole(module.STAKING_ROUTER_ROLE(), admin);
        module.grantRole(module.VERIFIER_ROLE(), admin);
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, 0);
        vm.stopPrank();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: true
        });

        vm.prank(actor);
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidatorsRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: true
        });

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportSlashedWithdrawnValidators(validatorInfos);
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

    function test_stakingRouterRole_updateExitedValidatorsCount_revert() public {
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

    function test_stakingRouterRole_updateTargetValidatorsLimits_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_stakingRouterRole_onExitedAndStuckValidatorsCountsUpdated() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onExitedAndStuckValidatorsCountsUpdated();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_noDepositable() public virtual {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_withDepositable() public virtual {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.expectRevert(IBaseModule.DepositableKeysWithUnsupportedWithdrawalCredentials.selector);
        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_RoleRevert() public {
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

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.ExitedSigningKeysCountChanged(noId, 0);
        vm.prank(actor);
        module.unsafeUpdateValidatorsCount(noId, 0);

        assertEq(module.getNonce(), nonce);
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

abstract contract ModuleMisc is ModuleFixtures {
    function test_getInitializedVersion() public view virtual {
        assertEq(module.getInitializedVersion(), 3);
    }

    function test_getActiveNodeOperatorsCount_OneOperator() public assertInvariants {
        createNodeOperator();
        uint256 noCount = module.getNodeOperatorsCount();
        assertEq(noCount, 1);
    }

    function test_getActiveNodeOperatorsCount_MultipleOperators() public assertInvariants {
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

    function test_getNodeOperatorIds_OffsetEqualsNodeOperatorsCount() public assertInvariants {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(3, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_OffsetHigherThanNodeOperatorsCount() public {
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

    function test_getNodeOperatorIds_ZeroLimitAndOffsetHigherThanNodeOperatorsCount() public {
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

    function test_getActiveNodeOperatorsCount_Multiple() public assertInvariants {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256 activeCount = module.getActiveNodeOperatorsCount();

        assertEq(activeCount, 3);
    }

    function test_getNodeOperatorManagementProperties() public assertInvariants {
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

        NodeOperatorManagementProperties memory props = module.getNodeOperatorManagementProperties(noId);
        assertEq(props.managerAddress, manager);
        assertEq(props.rewardAddress, reward);
        assertEq(props.extendedManagerPermissions, extended);
    }

    function test_getNodeOperatorManagementProperties_NoOperator() public assertInvariants {
        NodeOperatorManagementProperties memory props = module.getNodeOperatorManagementProperties(0);
        assertEq(props.managerAddress, address(0));
        assertEq(props.rewardAddress, address(0));
        assertFalse(props.extendedManagerPermissions);
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

    function test_getNodeOperatorOwner_ExtendedPermissions() public assertInvariants {
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
