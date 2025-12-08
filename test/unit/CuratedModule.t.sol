// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { CuratedModule } from "src/CuratedModule.sol";
import { Stub } from "../helpers/mocks/Stub.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { IBaseModule, INOAddresses, NodeOperator, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { CSModule } from "src/CSModule.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract.t.sol";

// TODO uncomment all the commented tests after implementing obtainDepositData

contract CuratedCommon is ModuleFixtures {
    CuratedModule cm;

    function moduleType() internal pure override returns (ModuleType) {
        return ModuleType.Curated;
    }

    function setUp() public virtual {
        nodeOperator = nextAddress("NODE_OPERATOR");
        stranger = nextAddress("STRANGER");
        strangerNumberTwo = nextAddress("STRANGER_TWO");
        admin = nextAddress("ADMIN");
        actor = nextAddress("ACTOR");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");
        stakingRouter = nextAddress("STAKING_ROUTER");

        (locator, wstETH, stETH, , ) = initLido();

        feeDistributor = new Stub();
        parametersRegistry = new ParametersRegistryMock();
        exitPenalties = new ExitPenaltiesMock();

        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: BOND_SIZE
        });
        accounting = new AccountingMock(
            BOND_SIZE,
            address(wstETH),
            address(stETH),
            address(feeDistributor)
        );

        module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        cm = CuratedModule(address(module));

        accounting.setModule(module);

        _enableInitializers(address(module));
        module.initialize({ admin: admin });

        vm.startPrank(admin);
        {
            module.grantRole(module.RESUME_ROLE(), address(admin));
            module.resume();
            module.revokeRole(module.RESUME_ROLE(), address(admin));
        }
        vm.stopPrank();

        _setupRolesForTests();
    }

    function _setupRolesForTests() internal virtual {
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        module.grantRole(module.PAUSE_ROLE(), address(this));
        module.grantRole(module.RESUME_ROLE(), address(this));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), stakingRouter);
        module.grantRole(
            module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        module.grantRole(
            module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        module.grantRole(module.VERIFIER_ROLE(), address(this));
        module.grantRole(module.SUBMIT_WITHDRAWALS_ROLE(), address(this));
        vm.stopPrank();
    }

    function _moduleInvariants() internal override {
        assertModuleKeys(module);
        assertModuleUnusedStorageSlots(module);
    }
}

contract CuratedCommonNoRoles is CuratedCommon {
    function _setupRolesForTests() internal override {
        vm.startPrank(admin);
        {
            // NOTE: Needed for the `createNodeOperator` helper.
            module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        }
        vm.stopPrank();
    }
}

contract CuratedFuzz is ModuleFuzz, CuratedCommon {}

contract CuratedInitialize is CuratedCommon {
    function test_constructor() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        assertEq(module.getType(), "curated-module");
        assertEq(address(module.LIDO_LOCATOR()), address(locator));
        assertEq(
            address(module.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
        assertEq(address(module.ACCOUNTING()), address(accounting));
        assertEq(address(module.EXIT_PENALTIES()), address(exitPenalties));
    }

    function test_constructor_RevertWhen_ZeroLocator() public {
        vm.expectRevert(IBaseModule.ZeroLocatorAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(0),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress()
        public
    {
        vm.expectRevert(IBaseModule.ZeroParametersRegistryAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(0),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroAccountingAddress() public {
        vm.expectRevert(IBaseModule.ZeroAccountingAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(0),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroExitPenaltiesAddress() public {
        vm.expectRevert(IBaseModule.ZeroExitPenaltiesAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(0)
        });
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: address(this) });
    }

    function test_initialize() public {
        CuratedModule module = new CuratedModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(module));
        module.initialize({ admin: address(this) });
        assertTrue(module.hasRole(module.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(module.getRoleMemberCount(module.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(module.isPaused());
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(module));
        vm.expectRevert(IBaseModule.ZeroAdminAddress.selector);
        module.initialize({ admin: address(0) });
    }
}

contract CuratedPauseTest is ModulePauseTest, CuratedCommon {}

contract CuratedPauseAffectingTest is ModulePauseAffectingTest, CuratedCommon {}

contract CuratedCreateNodeOperator is ModuleCreateNodeOperator, CuratedCommon {}

// contract CuratedAddValidatorKeys is ModuleAddValidatorKeys, CuratedCommon {}
// contract CuratedAddValidatorKeysViaGate is
//     ModuleAddValidatorKeysViaGate,
//     CuratedCommon
// {
//
// }

contract CuratedAddValidatorKeysNegative is
    ModuleAddValidatorKeysNegative,
    CuratedCommon
{

}

// contract CuratedObtainDepositData is ModuleObtainDepositData, CuratedCommon {}
contract CuratedProposeNodeOperatorManagerAddressChange is
    ModuleProposeNodeOperatorManagerAddressChange,
    CuratedCommon
{

}

contract CuratedConfirmNodeOperatorManagerAddressChange is
    ModuleConfirmNodeOperatorManagerAddressChange,
    CuratedCommon
{}

contract CuratedProposeNodeOperatorRewardAddressChange is
    ModuleProposeNodeOperatorRewardAddressChange,
    CuratedCommon
{}

contract CuratedConfirmNodeOperatorRewardAddressChange is
    ModuleConfirmNodeOperatorRewardAddressChange,
    CuratedCommon
{}

contract CuratedResetNodeOperatorManagerAddress is
    ModuleResetNodeOperatorManagerAddress,
    CuratedCommon
{}

contract CuratedChangeNodeOperatorRewardAddress is
    ModuleChangeNodeOperatorRewardAddress,
    CuratedCommon
{}

contract CuratedVetKeys is ModuleVetKeys, CuratedCommon {}

//contract CuratedQueueOps is ModuleQueueOps, CuratedCommon {}
//contract CuratedPriorityQueue is ModulePriorityQueue, CuratedCommon {}
//contract CuratedDecreaseVettedSigningKeysCount is ModuleDecreaseVettedSigningKeysCount, CuratedCommon {}
contract CuratedGetSigningKeys is ModuleGetSigningKeys, CuratedCommon {

}

contract CuratedGetSigningKeysWithSignatures is
    ModuleGetSigningKeysWithSignatures,
    CuratedCommon
{}

contract CuratedRemoveKeys is ModuleRemoveKeys, CuratedCommon {}

contract CuratedRemoveKeysChargeFee is
    ModuleRemoveKeysChargeFee,
    CuratedCommon
{}

//contract CuratedRemoveKeysReverts is ModuleRemoveKeysReverts, CuratedCommon {}
//contract CuratedGetNodeOperatorNonWithdrawnKeys is ModuleGetNodeOperatorNonWithdrawnKeys, CuratedCommon {}
//contract CuratedGetNodeOperatorSummary is ModuleGetNodeOperatorSummary, CuratedCommon {}
contract CuratedGetNodeOperator is ModuleGetNodeOperator, CuratedCommon {

}

contract CuratedUpdateTargetValidatorsLimits is
    ModuleUpdateTargetValidatorsLimits,
    CuratedCommon
{}

//contract CuratedUpdateExitedValidatorsCount is ModuleUpdateExitedValidatorsCount, CuratedCommon {}
//contract CuratedUnsafeUpdateValidatorsCount is ModuleUnsafeUpdateValidatorsCount, CuratedCommon {}
//contract CuratedReportGeneralDelayedPenalty is ModuleReportGeneralDelayedPenalty, CuratedCommon {}
contract CuratedCancelGeneralDelayedPenalty is
    ModuleCancelGeneralDelayedPenalty,
    CuratedCommon
{

}

contract CuratedSettleGeneralDelayedPenaltyBasic is
    ModuleSettleGeneralDelayedPenaltyBasic,
    CuratedCommon
{}

contract CuratedSettleGeneralDelayedPenaltyAdvanced is
    ModuleSettleGeneralDelayedPenaltyAdvanced,
    CuratedCommon
{}

//contract CuratedCompensateGeneralDelayedPenalty is ModuleCompensateGeneralDelayedPenalty, CuratedCommon {}
//contract CuratedSubmitWithdrawals is ModuleSubmitWithdrawals, CuratedCommon {}
//contract CuratedGetStakingModuleSummary is ModuleGetStakingModuleSummary, CuratedCommon {}
//contract CuratedAccessControl is ModuleAccessControl, CuratedCommonNoRoles {}
//contract CuratedStakingRouterAccessControl is ModuleStakingRouterAccessControl, CuratedCommonNoRoles {}
//contract CuratedDepositableValidatorsCount is ModuleDepositableValidatorsCount, CuratedCommon {}
//contract CuratedNodeOperatorStateAfterUpdateCurve is ModuleNodeOperatorStateAfterUpdateCurve, CuratedCommon {}
contract CuratedOnRewardsMinted is ModuleOnRewardsMinted, CuratedCommon {

}

contract CuratedRecoverERC20 is ModuleRecoverERC20, CuratedCommon {}

contract CuratedSupportsInterface is ModuleSupportsInterface, CuratedCommon {}

//contract CuratedMisc is ModuleMisc, CuratedCommon {}
contract CuratedExitDeadlineThreshold is
    ModuleExitDeadlineThreshold,
    CuratedCommon
{

}

contract CuratedIsValidatorExitDelayPenaltyApplicable is
    ModuleIsValidatorExitDelayPenaltyApplicable,
    CuratedCommon
{}

contract CuratedReportValidatorExitDelay is
    ModuleReportValidatorExitDelay,
    CuratedCommon
{}

contract CuratedOnValidatorExitTriggered is
    ModuleOnValidatorExitTriggered,
    CuratedCommon
{}

contract CuratedCreateNodeOperators is
    ModuleCreateNodeOperators,
    CuratedCommon
{}

contract CuratedChangeNodeOperatorAddresses is CuratedCommon {
    function test_changeNodeOperatorAddresses_NoExtendedManagerPermissions_SingleOwner()
        public
    {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            manager
        );

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            rewards
        );

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_NoExtendedManagerPermissions_SeparateManagerReward()
        public
    {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            managerToChange,
            manager
        );

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            rewardsToChange,
            rewards
        );

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ExtendedManagerPermissions_SingleOwner()
        public
    {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: true
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            manager
        );

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            rewards
        );

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ExtendedManagerPermissions_SeparateManagerReward()
        public
    {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: true
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            managerToChange,
            manager
        );

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            rewardsToChange,
            rewards
        );

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ChangesOnlyGivenAddress() public {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        uint256 snapshot = vm.snapshotState();

        {
            vm.expectEmit(address(cm));
            emit INOAddresses.NodeOperatorRewardAddressChanged(
                noId,
                rewardsToChange,
                rewards
            );

            vm.recordLogs();
            cm.changeNodeOperatorAddresses(noId, managerToChange, rewards);
            assertEq(vm.getRecordedLogs().length, 1);
        }
        vm.revertToState(snapshot);

        {
            vm.expectEmit(address(cm));
            emit INOAddresses.NodeOperatorManagerAddressChanged(
                noId,
                managerToChange,
                manager
            );

            vm.recordLogs();
            cm.changeNodeOperatorAddresses(noId, manager, rewardsToChange);
            assertEq(vm.getRecordedLogs().length, 1);
        }
        vm.revertToState(snapshot);
    }

    function test_changeNodeOperatorAddresses_RevertsIfOperatorDoesNotExist()
        public
    {
        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        cm.changeNodeOperatorAddresses(0, manager, rewards);
    }

    function test_changeNodeOperatorAddresses_RevertsIfHasNoRole() public {
        assertFalse(
            cm.hasRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this))
        );

        address manager = nextAddress();
        address rewards = nextAddress();

        expectRoleRevert(address(this), cm.OPERATOR_ADDRESSES_ADMIN_ROLE());
        cm.changeNodeOperatorAddresses(0, manager, rewards);
    }

    function test_changeNodeOperatorAddresses_RevertsIfTheSameAddresses()
        public
    {
        address manager = nextAddress();
        address rewards = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: rewards,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        vm.expectRevert(INOAddresses.SameAddress.selector);
        cm.changeNodeOperatorAddresses(noId, manager, rewards);
    }

    function test_changeNodeOperatorAddresses_RevertsIfZeroAddressProvided()
        public
    {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nextAddress(),
                rewardAddress: nextAddress(),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectRevert(INOAddresses.ZeroManagerAddress.selector);
        cm.changeNodeOperatorAddresses(noId, address(0), rewards);

        vm.expectRevert(INOAddresses.ZeroRewardAddress.selector);
        cm.changeNodeOperatorAddresses(noId, manager, address(0));
    }
}
