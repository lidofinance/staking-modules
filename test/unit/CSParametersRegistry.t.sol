// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { CSParametersRegistry } from "src/CSParametersRegistry.sol";
import { ICSParametersRegistry } from "src/interfaces/ICSParametersRegistry.sol";

import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract CSParametersRegistryBaseTest is Test, Utilities, Fixtures {
    address internal admin;
    address internal stranger;

    ICSParametersRegistry.InitializationData internal defaultInitData;

    CSParametersRegistry internal parametersRegistry;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        stranger = nextAddress("STRANGER");

        parametersRegistry = new CSParametersRegistry({
            queueLowestPriority: 5
        });

        defaultInitData = ICSParametersRegistry.InitializationData({
            defaultKeyRemovalCharge: 0.05 ether,
            defaultElRewardsStealingAdditionalFine: 0.1 ether,
            defaultKeysLimit: 100_000,
            defaultRewardShare: 8000,
            defaultPerformanceLeeway: 500,
            defaultStrikesLifetime: 6,
            defaultStrikesThreshold: 3,
            defaultQueuePriority: 0,
            defaultQueueMaxDeposits: 10,
            defaultBadPerformancePenalty: 0.1 ether,
            defaultAttestationsWeight: 54,
            defaultBlocksWeight: 8,
            defaultSyncWeight: 2,
            defaultAllowedExitDelay: 1 days,
            defaultExitDelayFee: 0.05 ether,
            defaultMaxWithdrawalRequestFee: 0.1 ether
        });
    }
}

contract CSParametersRegistryInitTest is CSParametersRegistryBaseTest {
    function test_constructor_RevertWhen_ZeroQueueLowestPriority() public {
        vm.expectRevert(ICSParametersRegistry.ZeroQueueLowestPriority.selector);
        new CSParametersRegistry({ queueLowestPriority: 0 });
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        parametersRegistry.initialize(admin, defaultInitData);
    }

    function test_initialize() public {
        _enableInitializers(address(parametersRegistry));

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeyRemovalChargeSet(
            defaultInitData.defaultKeyRemovalCharge
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultElRewardsStealingAdditionalFineSet(
            defaultInitData.defaultElRewardsStealingAdditionalFine
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeysLimitSet(
            defaultInitData.defaultKeysLimit
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultRewardShareSet(
            defaultInitData.defaultRewardShare
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceLeewaySet(
            defaultInitData.defaultPerformanceLeeway
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultStrikesParamsSet(
            defaultInitData.defaultStrikesLifetime,
            defaultInitData.defaultStrikesThreshold
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultBadPerformancePenaltySet(
            defaultInitData.defaultBadPerformancePenalty
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceCoefficientsSet(
            defaultInitData.defaultAttestationsWeight,
            defaultInitData.defaultBlocksWeight,
            defaultInitData.defaultSyncWeight
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultQueueConfigSet(
            defaultInitData.defaultQueuePriority,
            defaultInitData.defaultQueueMaxDeposits
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultAllowedExitDelaySet(
            defaultInitData.defaultAllowedExitDelay
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultExitDelayFeeSet(
            defaultInitData.defaultExitDelayFee
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultMaxWithdrawalRequestFeeSet(
            defaultInitData.defaultMaxWithdrawalRequestFee
        );

        parametersRegistry.initialize(admin, defaultInitData);

        assertTrue(
            parametersRegistry.hasRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertEq(
            parametersRegistry.defaultKeyRemovalCharge(),
            defaultInitData.defaultKeyRemovalCharge
        );
        assertEq(
            parametersRegistry.defaultElRewardsStealingAdditionalFine(),
            defaultInitData.defaultElRewardsStealingAdditionalFine
        );
        assertEq(
            parametersRegistry.defaultKeysLimit(),
            defaultInitData.defaultKeysLimit
        );

        (uint256 priority, uint256 maxDeposits) = parametersRegistry
            .defaultQueueConfig();

        assertEq(priority, defaultInitData.defaultQueuePriority);
        assertEq(maxDeposits, defaultInitData.defaultQueueMaxDeposits);

        assertEq(
            parametersRegistry.defaultRewardShare(),
            defaultInitData.defaultRewardShare
        );
        assertEq(
            parametersRegistry.defaultPerformanceLeeway(),
            defaultInitData.defaultPerformanceLeeway
        );

        (uint256 lifetime, uint256 threshold) = parametersRegistry
            .defaultStrikesParams();

        assertEq(lifetime, defaultInitData.defaultStrikesLifetime);
        assertEq(threshold, defaultInitData.defaultStrikesThreshold);

        assertEq(
            parametersRegistry.defaultBadPerformancePenalty(),
            defaultInitData.defaultBadPerformancePenalty
        );

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.defaultPerformanceCoefficients();

        assertEq(attestationsOut, defaultInitData.defaultAttestationsWeight);
        assertEq(blocksOut, defaultInitData.defaultBlocksWeight);
        assertEq(syncOut, defaultInitData.defaultSyncWeight);

        assertEq(
            parametersRegistry.defaultAllowedExitDelay(),
            defaultInitData.defaultAllowedExitDelay
        );
        assertEq(
            parametersRegistry.defaultExitDelayFee(),
            defaultInitData.defaultExitDelayFee
        );
        assertEq(
            parametersRegistry.defaultMaxWithdrawalRequestFee(),
            defaultInitData.defaultMaxWithdrawalRequestFee
        );

        assertEq(parametersRegistry.getInitializedVersion(), 1);
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        _enableInitializers(address(parametersRegistry));
        vm.expectRevert(ICSParametersRegistry.ZeroAdminAddress.selector);
        parametersRegistry.initialize(address(0), defaultInitData);
    }

    function test_initialize_RevertWhen_InvalidDefaultRewardShare() public {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultRewardShare = 10001;

        vm.expectRevert(ICSParametersRegistry.InvalidRewardShareData.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidDefaultPerformanceLeeway()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultPerformanceLeeway = 10001;

        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceLeewayData.selector
        );
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidStrikesParams_zeroLifetime()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultStrikesLifetime = 0;
        customInitData.defaultStrikesThreshold = 1;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidStrikesParams_zeroThreshold()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultStrikesLifetime = 1;
        customInitData.defaultStrikesThreshold = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidPriorityQueueId_QueueIdGreaterThanAllowed()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultQueuePriority =
            parametersRegistry.QUEUE_LOWEST_PRIORITY() +
            1;

        vm.expectRevert(ICSParametersRegistry.QueueCannotBeUsed.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_ZeroPriorityQueueMaxDeposits() public {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultQueueMaxDeposits = 0;

        vm.expectRevert(ICSParametersRegistry.ZeroMaxDeposits.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidPerformanceCoefficients()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.defaultAttestationsWeight = 0;
        customInitData.defaultBlocksWeight = 0;
        customInitData.defaultSyncWeight = 0;

        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceCoefficients.selector
        );
        parametersRegistry.initialize(admin, customInitData);
    }
}

abstract contract ParametersTest {
    function test_setDefault() public virtual;

    function test_setDefault_FromRoleAdmin() public virtual;

    function test_setDefault_RevertWhen_noRole() public virtual;

    function test_set() public virtual;

    function test_set_FromRoleAdmin() public virtual;

    function test_set_RevertWhen_noRole() public virtual;

    function test_unset() public virtual;

    function test_unset_FromRoleAdmin() public virtual;

    function test_unset_RevertWhen_noRole() public virtual;

    function test_get_usualData() public virtual;

    function test_get_defaultData() public virtual;
}

contract CSParametersRegistryBaseTestInitialized is
    CSParametersRegistryBaseTest
{
    address roleMember;

    function setUp() public virtual override {
        super.setUp();
        _enableInitializers(address(parametersRegistry));
        parametersRegistry.initialize(admin, defaultInitData);
        roleMember = nextAddress("ROLE_MEMBER");
    }
}

contract CSParametersRegistryRewardShareDataTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_REWARD_SHARE_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_InvalidRewardShareData() public {
        uint256 rewardShare = 70001;

        vm.expectRevert(ICSParametersRegistry.InvalidRewardShareData.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultRewardShare(rewardShare);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 rewardShare = 70001;

        bytes32 role = parametersRegistry.MANAGE_REWARD_SHARE_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultRewardShare(rewardShare);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_Overwrite() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory first = new ICSParametersRegistry.KeyNumberValueInterval[](
                2
            );
        first[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        first[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, first);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory second = new ICSParametersRegistry.KeyNumberValueInterval[](
                1
            );
        second[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 777);

        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, second);

        CSParametersRegistry.KeyNumberValueInterval[]
            memory result = parametersRegistry.getRewardShareData(1);

        assertEq(result.length, 1);
        assertEq(result[0].minKeyNumber, 1);
        assertEq(result[0].value, 777);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        bytes32 role = parametersRegistry.MANAGE_REWARD_SHARE_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_set_RevertWhen_invalidIntervalsSort() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](3);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 8000);
        data[2] = ICSParametersRegistry.KeyNumberValueInterval(10, 5000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_set_RevertWhen_firstIntervalStartsFromNotOne() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](1);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(100, 10000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_set_RevertWhen_invalidBpValues() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 100000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_set_RevertWhen_emptyIntervals() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](0);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_set_RevertWhen_invalidBpValues_nonFirstItem() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 8000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 80000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_REWARD_SHARE_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetRewardShareData(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getRewardShareData(curveId);

        assertEq(dataOut.length, data.length);
        for (uint256 i = 0; i < dataOut.length; ++i) {
            assertEq(dataOut[i].minKeyNumber, data[i].minKeyNumber);
            assertEq(dataOut[i].value, data[i].value);
        }
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getRewardShareData(curveId);

        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.defaultRewardShare);
    }

    function _test_set_default(address from) internal {
        uint256 rewardShare = 700;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultRewardShareSet(rewardShare);
        vm.prank(from);
        parametersRegistry.setDefaultRewardShare(rewardShare);

        assertEq(parametersRegistry.defaultRewardShare(), rewardShare);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.RewardShareDataSet(curveId, data);
        vm.prank(from);
        parametersRegistry.setRewardShareData(curveId, data);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.prank(from);
        parametersRegistry.setRewardShareData(curveId, data);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getRewardShareData(curveId);

        assertEq(dataOut.length, data.length);
        for (uint256 i = 0; i < dataOut.length; ++i) {
            assertEq(dataOut[i].minKeyNumber, data[i].minKeyNumber);
            assertEq(dataOut[i].value, data[i].value);
        }

        vm.prank(from);
        parametersRegistry.unsetRewardShareData(curveId);

        dataOut = parametersRegistry.getRewardShareData(curveId);
        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.defaultRewardShare);
    }
}

contract CSParametersRegistryPerformanceLeewayDataTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 leeway = 700;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultPerformanceLeeway(leeway);
    }

    function test_setDefault_RevertWhen_InvalidRewardShareData() public {
        uint256 leeway = 20001;
        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceLeewayData.selector
        );
        vm.prank(admin);
        parametersRegistry.setDefaultPerformanceLeeway(leeway);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_Overwrite() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory first = new ICSParametersRegistry.KeyNumberValueInterval[](
                2
            );
        first[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        first[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, first);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory second = new ICSParametersRegistry.KeyNumberValueInterval[](
                1
            );
        second[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 777);

        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, second);

        CSParametersRegistry.KeyNumberValueInterval[]
            memory result = parametersRegistry.getPerformanceLeewayData(1);

        assertEq(result.length, 1);
        assertEq(result[0].minKeyNumber, 1);
        assertEq(result[0].value, 777);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function test_set_RevertWhen_invalidIntervalsSort() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](3);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);
        data[2] = ICSParametersRegistry.KeyNumberValueInterval(10, 300);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function test_set_RevertWhen_firstIntervalStartsFromNotOne() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](1);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(100, 10000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function test_set_RevertWhen_invalidBpValues() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 100000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function test_set_RevertWhen_emptyIntervals() public {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](0);

        vm.expectRevert(
            ICSParametersRegistry.InvalidKeyNumberValueIntervals.selector
        );
        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetPerformanceLeewayData(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getPerformanceLeewayData(
                curveId
            );

        assertEq(dataOut.length, data.length);
        for (uint256 i = 0; i < dataOut.length; ++i) {
            assertEq(dataOut[i].minKeyNumber, data[i].minKeyNumber);
            assertEq(dataOut[i].value, data[i].value);
        }
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getPerformanceLeewayData(
                curveId
            );

        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.defaultPerformanceLeeway);
    }

    function _test_set_default(address from) internal {
        uint256 leeway = 700;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceLeewaySet(leeway);
        vm.prank(from);
        parametersRegistry.setDefaultPerformanceLeeway(leeway);

        assertEq(parametersRegistry.defaultPerformanceLeeway(), leeway);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.PerformanceLeewayDataSet(curveId, data);
        vm.prank(from);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 450);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        vm.prank(from);
        parametersRegistry.setPerformanceLeewayData(curveId, data);

        ICSParametersRegistry.KeyNumberValueInterval[]
            memory dataOut = parametersRegistry.getPerformanceLeewayData(
                curveId
            );

        assertEq(dataOut.length, data.length);
        for (uint256 i = 0; i < dataOut.length; ++i) {
            assertEq(dataOut[i].minKeyNumber, data[i].minKeyNumber);
            assertEq(dataOut[i].value, data[i].value);
        }

        vm.prank(from);
        parametersRegistry.unsetPerformanceLeewayData(curveId);

        dataOut = parametersRegistry.getPerformanceLeewayData(curveId);

        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.defaultPerformanceLeeway);
    }
}

contract CSParametersRegistryKeyRemovalChargeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 charge = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultKeyRemovalCharge(charge);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetKeyRemovalCharge(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        vm.prank(admin);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);

        uint256 chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, charge);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, defaultInitData.defaultKeyRemovalCharge);
    }

    function _test_set_default(address from) internal {
        uint256 charge = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeyRemovalChargeSet(charge);
        vm.prank(from);
        parametersRegistry.setDefaultKeyRemovalCharge(charge);

        assertEq(parametersRegistry.defaultKeyRemovalCharge(), charge);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.KeyRemovalChargeSet(curveId, charge);
        vm.prank(from);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        vm.prank(from);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);

        uint256 chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, charge);

        vm.prank(from);
        parametersRegistry.unsetKeyRemovalCharge(curveId);

        chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, defaultInitData.defaultKeyRemovalCharge);
    }
}

contract CSParametersRegistryElRewardsStealingAdditionalFineTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 fine = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultElRewardsStealingAdditionalFine(fine);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry
            .MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetElRewardsStealingAdditionalFine(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        vm.prank(admin);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);

        uint256 fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(fineOut, fine);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(
            fineOut,
            defaultInitData.defaultElRewardsStealingAdditionalFine
        );
    }

    function _test_set_default(address from) internal {
        uint256 fine = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultElRewardsStealingAdditionalFineSet(
            fine
        );
        vm.prank(from);
        parametersRegistry.setDefaultElRewardsStealingAdditionalFine(fine);

        assertEq(
            parametersRegistry.defaultElRewardsStealingAdditionalFine(),
            fine
        );
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.ElRewardsStealingAdditionalFineSet(
            curveId,
            fine
        );
        vm.prank(from);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        vm.prank(from);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);

        uint256 fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(fineOut, fine);

        vm.prank(from);
        parametersRegistry.unsetElRewardsStealingAdditionalFine(curveId);

        fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(
            fineOut,
            defaultInitData.defaultElRewardsStealingAdditionalFine
        );
    }
}

contract CSParametersRegistryKeysLimitTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_KEYS_LIMIT_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 limit = 1000;

        bytes32 role = parametersRegistry.MANAGE_KEYS_LIMIT_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultKeysLimit(limit);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 limit = 1000;

        bytes32 role = parametersRegistry.MANAGE_KEYS_LIMIT_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setKeysLimit(curveId, limit);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_KEYS_LIMIT_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetKeysLimit(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 limit = 1000;

        vm.prank(admin);
        parametersRegistry.setKeysLimit(curveId, limit);

        uint256 limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, limit);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, defaultInitData.defaultKeysLimit);
    }

    function _test_set_default(address from) internal {
        uint256 limit = 1000;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeysLimitSet(limit);
        vm.prank(from);
        parametersRegistry.setDefaultKeysLimit(limit);

        assertEq(parametersRegistry.defaultKeysLimit(), limit);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 limit = 1000;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.KeysLimitSet(curveId, limit);
        vm.prank(from);
        parametersRegistry.setKeysLimit(curveId, limit);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 limit = 1000;

        vm.prank(from);
        parametersRegistry.setKeysLimit(curveId, limit);

        uint256 limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, limit);

        vm.prank(from);
        parametersRegistry.unsetKeysLimit(curveId);

        limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, defaultInitData.defaultKeysLimit);
    }
}

contract CSParametersRegistryStrikesParamsTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_zeroLifetime() public {
        uint256 lifetime = 0;
        uint256 threshold = 1;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);
    }

    function test_setDefault_RevertWhen_zeroThreshold() public {
        uint256 lifetime = 1;
        uint256 threshold = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 lifetime = 12;
        uint256 threshold = 6;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_zeroLifetime() public {
        uint256 curveId = 1;
        uint256 lifetime = 0;
        uint256 threshold = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        vm.prank(admin);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
    }

    function test_set_RevertWhen_zeroThreshold() public {
        uint256 curveId = 1;
        uint256 lifetime = 1;
        uint256 threshold = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        vm.prank(admin);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 lifetime = 3;
        uint256 threshold = 2;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetStrikesParams(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 lifetime = 3;
        uint256 threshold = 2;

        vm.prank(admin);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);

        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .getStrikesParams(curveId);

        assertEq(lifetimeOut, lifetime);
        assertEq(thresholdOut, threshold);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .getStrikesParams(curveId);

        assertEq(lifetimeOut, defaultInitData.defaultStrikesLifetime);
        assertEq(thresholdOut, defaultInitData.defaultStrikesThreshold);
    }

    function _test_set_default(address from) internal {
        uint256 lifetime = 12;
        uint256 threshold = 6;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultStrikesParamsSet(lifetime, threshold);
        vm.prank(from);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);

        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .defaultStrikesParams();

        assertEq(lifetimeOut, lifetime);
        assertEq(thresholdOut, threshold);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 lifetime = 8;
        uint256 threshold = 2;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.StrikesParamsSet(
            curveId,
            lifetime,
            threshold
        );
        vm.prank(from);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 lifetime = 3;
        uint256 threshold = 2;

        vm.prank(from);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);

        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .getStrikesParams(curveId);

        assertEq(lifetimeOut, lifetime);
        assertEq(thresholdOut, threshold);

        vm.prank(from);
        parametersRegistry.unsetStrikesParams(curveId);

        (lifetimeOut, thresholdOut) = parametersRegistry.getStrikesParams(
            curveId
        );

        assertEq(lifetimeOut, defaultInitData.defaultStrikesLifetime);
        assertEq(thresholdOut, defaultInitData.defaultStrikesThreshold);
    }
}

contract CSParametersRegistryBadPerformancePenaltyTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultBadPerformancePenalty(penalty);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setBadPerformancePenalty(curveId, penalty);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetBadPerformancePenalty(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 expectedPenalty = 1 ether;

        vm.prank(admin);
        parametersRegistry.setBadPerformancePenalty(curveId, expectedPenalty);

        uint256 penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, expectedPenalty);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, defaultInitData.defaultBadPerformancePenalty);
    }

    function _test_set_default(address from) internal {
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultBadPerformancePenaltySet(penalty);
        vm.prank(from);
        parametersRegistry.setDefaultBadPerformancePenalty(penalty);

        assertEq(parametersRegistry.defaultBadPerformancePenalty(), penalty);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.BadPerformancePenaltySet(curveId, penalty);
        vm.prank(from);
        parametersRegistry.setBadPerformancePenalty(curveId, penalty);

        assertEq(parametersRegistry.getBadPerformancePenalty(curveId), penalty);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 expectedPenalty = 1 ether;

        vm.prank(from);
        parametersRegistry.setBadPerformancePenalty(curveId, expectedPenalty);

        uint256 penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, expectedPenalty);

        vm.prank(from);
        parametersRegistry.unsetBadPerformancePenalty(curveId);

        penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, defaultInitData.defaultBadPerformancePenalty);
    }
}

contract CSParametersRegistryPerformanceCoefficientsTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 attestations = 110;
        uint256 blocks = 25;
        uint256 sync = 10;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultPerformanceCoefficients(
            attestations,
            blocks,
            sync
        );
    }

    function test_setDefault_RevertWhen_InvalidPerformanceCoefficients()
        public
    {
        uint256 attestations = 0;
        uint256 blocks = 0;
        uint256 sync = 0;

        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceCoefficients.selector
        );
        vm.prank(admin);
        parametersRegistry.setDefaultPerformanceCoefficients(
            attestations,
            blocks,
            sync
        );
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 attestations = 100;
        uint256 blocks = 20;
        uint256 sync = 5;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );
    }

    function test_set_RevertWhen_InvalidPerformanceCoefficients() public {
        uint256 curveId = 1;
        uint256 attestations = 0;
        uint256 blocks = 0;
        uint256 sync = 0;

        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceCoefficients.selector
        );
        vm.prank(admin);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.MANAGE_PERFORMANCE_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetPerformanceCoefficients(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 attestations = 100;
        uint256 blocks = 20;
        uint256 sync = 5;

        vm.prank(admin);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.getPerformanceCoefficients(curveId);

        assertEq(attestationsOut, attestations);
        assertEq(blocksOut, blocks);
        assertEq(syncOut, sync);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.getPerformanceCoefficients(curveId);

        assertEq(attestationsOut, defaultInitData.defaultAttestationsWeight);
        assertEq(blocksOut, defaultInitData.defaultBlocksWeight);
        assertEq(syncOut, defaultInitData.defaultSyncWeight);
    }

    function _test_set_default(address from) internal {
        uint256 attestations = 110;
        uint256 blocks = 25;
        uint256 sync = 10;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceCoefficientsSet(
            attestations,
            blocks,
            sync
        );
        vm.prank(from);
        parametersRegistry.setDefaultPerformanceCoefficients(
            attestations,
            blocks,
            sync
        );

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.defaultPerformanceCoefficients();

        assertEq(attestationsOut, attestations);
        assertEq(blocksOut, blocks);
        assertEq(syncOut, sync);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 attestations = 100;
        uint256 blocks = 20;
        uint256 sync = 5;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.PerformanceCoefficientsSet(
            curveId,
            attestations,
            blocks,
            sync
        );
        vm.prank(from);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 attestations = 100;
        uint256 blocks = 20;
        uint256 sync = 5;

        vm.prank(from);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.getPerformanceCoefficients(curveId);

        assertEq(attestationsOut, attestations);
        assertEq(blocksOut, blocks);
        assertEq(syncOut, sync);

        vm.prank(from);
        parametersRegistry.unsetPerformanceCoefficients(curveId);

        (attestationsOut, blocksOut, syncOut) = parametersRegistry
            .getPerformanceCoefficients(curveId);

        assertEq(attestationsOut, defaultInitData.defaultAttestationsWeight);
        assertEq(blocksOut, defaultInitData.defaultBlocksWeight);
        assertEq(syncOut, defaultInitData.defaultSyncWeight);
    }
}

contract CSParametersRegistryQueueConfigTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_QUEUE_CONFIG_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        bytes32 role = parametersRegistry.MANAGE_QUEUE_CONFIG_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultQueueConfig(priority, maxDeposits);
    }

    function test_setDefault_RevertWhen_QueuePriorityAboveLimit() public {
        uint32 priority = uint32(parametersRegistry.QUEUE_LOWEST_PRIORITY()) +
            1;
        uint32 maxDeposits = 42;

        vm.expectRevert(ICSParametersRegistry.QueueCannotBeUsed.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultQueueConfig(priority, maxDeposits);
    }

    function test_setDefault_RevertWhen_ZeroMaxDeposits() public {
        uint32 priority = 1;
        uint32 maxDeposits = 0;

        vm.expectRevert(ICSParametersRegistry.ZeroMaxDeposits.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultQueueConfig(priority, maxDeposits);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        bytes32 role = parametersRegistry.MANAGE_QUEUE_CONFIG_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 11;
        bytes32 role = parametersRegistry.MANAGE_QUEUE_CONFIG_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetQueueConfig(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.QueueConfigSet(
            curveId,
            priority,
            maxDeposits
        );
        vm.prank(admin);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .getQueueConfig(curveId);
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 11;

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .getQueueConfig(curveId);
        assertEq(priorityOut, defaultInitData.defaultQueuePriority);
        assertEq(maxDepositsOut, defaultInitData.defaultQueueMaxDeposits);
    }

    function test_set_RevertWhen_QueuePriorityAboveLimit() public {
        uint256 curveId = 11;
        uint32 priority = uint32(parametersRegistry.QUEUE_LOWEST_PRIORITY()) +
            1;
        uint32 maxDeposits = 42;

        vm.expectRevert(ICSParametersRegistry.QueueCannotBeUsed.selector);
        vm.prank(admin);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);
    }

    function test_set_RevertWhen_ZeroMaxDeposits() public {
        uint256 curveId = 11;
        uint32 priority = 1;
        uint32 maxDeposits = 0;

        vm.expectRevert(ICSParametersRegistry.ZeroMaxDeposits.selector);
        vm.prank(admin);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);
    }

    function _test_set_default(address from) internal {
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultQueueConfigSet(priority, maxDeposits);
        vm.prank(from);
        parametersRegistry.setDefaultQueueConfig(priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .defaultQueueConfig();
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);
    }

    function _test_set(address from) internal {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.QueueConfigSet(
            curveId,
            priority,
            maxDeposits
        );
        vm.prank(from);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .getQueueConfig(curveId);
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.prank(from);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .getQueueConfig(curveId);
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.QueueConfigUnset(curveId);
        vm.prank(from);
        parametersRegistry.unsetQueueConfig(curveId);

        (priorityOut, maxDepositsOut) = parametersRegistry.getQueueConfig(
            curveId
        );
        assertEq(priorityOut, defaultInitData.defaultQueuePriority);
        assertEq(maxDepositsOut, defaultInitData.defaultQueueMaxDeposits);
    }
}

contract CSParametersRegistryAllowedExitDelayTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_InvalidAllowedExitDelay() public {
        uint256 delay = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidAllowedExitDelay.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultAllowedExitDelay(delay);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 delay = 7 days;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultAllowedExitDelay(delay);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_InvalidAllowedExitDelay() public {
        uint256 curveId = 1;
        uint256 delay = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidAllowedExitDelay.selector);
        vm.prank(admin);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetAllowedExitDelay(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        vm.prank(admin);
        parametersRegistry.setAllowedExitDelay(curveId, delay);

        uint256 delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, delay);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, defaultInitData.defaultAllowedExitDelay);
    }

    function _test_set_default(address from) internal {
        uint256 delay = 7 days;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultAllowedExitDelaySet(delay);
        vm.prank(from);
        parametersRegistry.setDefaultAllowedExitDelay(delay);

        assertEq(parametersRegistry.defaultAllowedExitDelay(), delay);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.AllowedExitDelaySet(curveId, delay);
        vm.prank(from);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        vm.prank(from);
        parametersRegistry.setAllowedExitDelay(curveId, delay);

        uint256 delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, delay);

        vm.prank(from);
        parametersRegistry.unsetAllowedExitDelay(curveId);

        delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, defaultInitData.defaultAllowedExitDelay);
    }
}

contract CSParametersRegistryExitDelayFeeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultExitDelayFee(penalty);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setExitDelayFee(curveId, penalty);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetExitDelayFee(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.prank(admin);
        parametersRegistry.setExitDelayFee(curveId, penalty);

        uint256 penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, penalty);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, defaultInitData.defaultExitDelayFee);
    }

    function _test_set_default(address from) internal {
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultExitDelayFeeSet(penalty);
        vm.prank(from);
        parametersRegistry.setDefaultExitDelayFee(penalty);

        assertEq(parametersRegistry.defaultExitDelayFee(), penalty);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.ExitDelayFeeSet(curveId, penalty);
        vm.prank(from);
        parametersRegistry.setExitDelayFee(curveId, penalty);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.prank(from);
        parametersRegistry.setExitDelayFee(curveId, penalty);

        uint256 penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, penalty);

        vm.prank(from);
        parametersRegistry.unsetExitDelayFee(curveId);

        penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, defaultInitData.defaultExitDelayFee);
    }
}

contract CSParametersRegistryMaxWithdrawalRequestFeeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        parametersRegistry.grantRole(
            parametersRegistry.MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE(),
            roleMember
        );
        vm.stopPrank();
    }

    function test_setDefault() public override {
        _test_set_default(roleMember);
    }

    function test_setDefault_FromRoleAdmin() public override {
        _test_set_default(admin);
    }

    function test_setDefault_RevertWhen_noRole() public override {
        uint256 fee = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultMaxWithdrawalRequestFee(fee);
    }

    function test_set() public override {
        _test_set(roleMember);
    }

    function test_set_FromRoleAdmin() public override {
        _test_set(admin);
    }

    function test_set_RevertWhen_noRole() public override {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);
    }

    function test_unset() public override {
        _test_unset(roleMember);
    }

    function test_unset_FromRoleAdmin() public override {
        _test_unset(admin);
    }

    function test_unset_RevertWhen_noRole() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry
            .MANAGE_VALIDATOR_EXIT_PARAMETERS_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.unsetMaxWithdrawalRequestFee(curveId);
    }

    function test_get_usualData() public override {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        vm.prank(admin);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);

        uint256 feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, fee);
    }

    function test_get_defaultData() public view override {
        uint256 curveId = 10;
        uint256 feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, defaultInitData.defaultMaxWithdrawalRequestFee);
    }

    function _test_set_default(address from) internal {
        uint256 fee = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultMaxWithdrawalRequestFeeSet(fee);
        vm.prank(from);
        parametersRegistry.setDefaultMaxWithdrawalRequestFee(fee);

        assertEq(parametersRegistry.defaultMaxWithdrawalRequestFee(), fee);
    }

    function _test_set(address from) internal {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.MaxWithdrawalRequestFeeSet(curveId, fee);
        vm.prank(from);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);
    }

    function _test_unset(address from) internal {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        vm.prank(from);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);

        uint256 feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, fee);

        vm.prank(from);
        parametersRegistry.unsetMaxWithdrawalRequestFee(curveId);

        feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, defaultInitData.defaultMaxWithdrawalRequestFee);
    }
}
