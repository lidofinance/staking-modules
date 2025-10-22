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
            keyRemovalCharge: 0.05 ether,
            elRewardsStealingAdditionalFine: 0.1 ether,
            keysLimit: 100_000,
            rewardShare: 8000,
            performanceLeeway: 500,
            strikesLifetime: 6,
            strikesThreshold: 3,
            defaultQueuePriority: 0,
            defaultQueueMaxDeposits: 10,
            badPerformancePenalty: 0.1 ether,
            attestationsWeight: 54,
            blocksWeight: 8,
            syncWeight: 2,
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
            defaultInitData.keyRemovalCharge
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultElRewardsStealingAdditionalFineSet(
            defaultInitData.elRewardsStealingAdditionalFine
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeysLimitSet(
            defaultInitData.keysLimit
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultRewardShareSet(
            defaultInitData.rewardShare
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceLeewaySet(
            defaultInitData.performanceLeeway
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultStrikesParamsSet(
            defaultInitData.strikesLifetime,
            defaultInitData.strikesThreshold
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultBadPerformancePenaltySet(
            defaultInitData.badPerformancePenalty
        );
        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceCoefficientsSet(
            defaultInitData.attestationsWeight,
            defaultInitData.blocksWeight,
            defaultInitData.syncWeight
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
        parametersRegistry.initialize(admin, defaultInitData);

        assertTrue(
            parametersRegistry.hasRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertEq(
            parametersRegistry.defaultKeyRemovalCharge(),
            defaultInitData.keyRemovalCharge
        );
        assertEq(
            parametersRegistry.defaultElRewardsStealingAdditionalFine(),
            defaultInitData.elRewardsStealingAdditionalFine
        );
        assertEq(
            parametersRegistry.defaultKeysLimit(),
            defaultInitData.keysLimit
        );
        assertEq(
            parametersRegistry.defaultRewardShare(),
            defaultInitData.rewardShare
        );
        assertEq(
            parametersRegistry.defaultPerformanceLeeway(),
            defaultInitData.performanceLeeway
        );

        (uint256 lifetime, uint256 threshold) = parametersRegistry
            .defaultStrikesParams();

        assertEq(lifetime, defaultInitData.strikesLifetime);
        assertEq(threshold, defaultInitData.strikesThreshold);

        (uint256 priority, uint256 maxDeposits) = parametersRegistry
            .defaultQueueConfig();

        assertEq(priority, defaultInitData.defaultQueuePriority);
        assertEq(maxDeposits, defaultInitData.defaultQueueMaxDeposits);

        assertEq(
            parametersRegistry.defaultBadPerformancePenalty(),
            defaultInitData.badPerformancePenalty
        );

        (
            uint256 attestationsOut,
            uint256 blocksOut,
            uint256 syncOut
        ) = parametersRegistry.defaultPerformanceCoefficients();

        assertEq(attestationsOut, defaultInitData.attestationsWeight);
        assertEq(blocksOut, defaultInitData.blocksWeight);
        assertEq(syncOut, defaultInitData.syncWeight);

        assertEq(
            parametersRegistry.defaultAllowedExitDelay(),
            defaultInitData.defaultAllowedExitDelay
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

        customInitData.rewardShare = 10001;

        vm.expectRevert(ICSParametersRegistry.InvalidRewardShareData.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidDefaultPerformanceLeeway()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.performanceLeeway = 10001;

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

        customInitData.strikesLifetime = 0;
        customInitData.strikesThreshold = 1;

        vm.expectRevert(ICSParametersRegistry.InvalidStrikesParams.selector);
        parametersRegistry.initialize(admin, customInitData);
    }

    function test_initialize_RevertWhen_InvalidStrikesParams_zeroThreshold()
        public
    {
        _enableInitializers(address(parametersRegistry));

        ICSParametersRegistry.InitializationData
            memory customInitData = defaultInitData;

        customInitData.strikesLifetime = 1;
        customInitData.strikesThreshold = 0;

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

        customInitData.attestationsWeight = 0;
        customInitData.blocksWeight = 0;
        customInitData.syncWeight = 0;

        vm.expectRevert(
            ICSParametersRegistry.InvalidPerformanceCoefficients.selector
        );
        parametersRegistry.initialize(admin, customInitData);
    }
}

abstract contract ParametersTest {
    function test_setDefault() public virtual;

    function test_setDefault_RevertWhen_notAdmin() public virtual;

    function test_set() public virtual;

    function test_set_RevertWhen_notAdmin() public virtual;

    function test_unset() public virtual;

    function test_unset_RevertWhen_notAdmin() public virtual;

    function test_get_usualData() public virtual;

    function test_get_defaultData() public virtual;
}

contract CSParametersRegistryBaseTestInitialized is
    CSParametersRegistryBaseTest
{
    function setUp() public virtual override {
        super.setUp();
        _enableInitializers(address(parametersRegistry));
        parametersRegistry.initialize(admin, defaultInitData);
    }
}

contract CSParametersRegistryRewardShareDataTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 rewardShare = 700;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultRewardShareSet(rewardShare);
        vm.prank(admin);
        parametersRegistry.setDefaultRewardShare(rewardShare);

        assertEq(parametersRegistry.defaultRewardShare(), rewardShare);
    }

    function test_setDefault_RevertWhen_InvalidRewardShareData() public {
        uint256 rewardShare = 70001;

        vm.expectRevert(ICSParametersRegistry.InvalidRewardShareData.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultRewardShare(rewardShare);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 rewardShare = 70001;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultRewardShare(rewardShare);
    }

    function test_set() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.RewardShareDataSet(curveId, data);
        vm.prank(admin);
        parametersRegistry.setRewardShareData(curveId, data);
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

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 10000);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(10, 8000);

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        vm.prank(admin);
        parametersRegistry.unsetRewardShareData(curveId);

        dataOut = parametersRegistry.getRewardShareData(curveId);
        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.rewardShare);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
        assertEq(dataOut[0].value, defaultInitData.rewardShare);
    }
}

contract CSParametersRegistryPerformanceLeewayDataTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 leeway = 700;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceLeewaySet(leeway);
        vm.prank(admin);
        parametersRegistry.setDefaultPerformanceLeeway(leeway);

        assertEq(parametersRegistry.defaultPerformanceLeeway(), leeway);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 leeway = 700;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.PerformanceLeewayDataSet(curveId, data);
        vm.prank(admin);
        parametersRegistry.setPerformanceLeewayData(curveId, data);
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

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 500);
        data[1] = ICSParametersRegistry.KeyNumberValueInterval(100, 400);

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
        uint256 curveId = 1;
        ICSParametersRegistry.KeyNumberValueInterval[]
            memory data = new ICSParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = ICSParametersRegistry.KeyNumberValueInterval(1, 450);
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

        vm.prank(admin);
        parametersRegistry.unsetPerformanceLeewayData(curveId);

        dataOut = parametersRegistry.getPerformanceLeewayData(curveId);

        assertEq(dataOut.length, 1);
        assertEq(dataOut[0].minKeyNumber, 1);
        assertEq(dataOut[0].value, defaultInitData.performanceLeeway);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
        assertEq(dataOut[0].value, defaultInitData.performanceLeeway);
    }
}

contract CSParametersRegistryKeyRemovalChargeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 charge = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeyRemovalChargeSet(charge);
        vm.prank(admin);
        parametersRegistry.setDefaultKeyRemovalCharge(charge);

        assertEq(parametersRegistry.defaultKeyRemovalCharge(), charge);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 charge = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultKeyRemovalCharge(charge);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.KeyRemovalChargeSet(curveId, charge);
        vm.prank(admin);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 charge = 1 ether;

        vm.prank(admin);
        parametersRegistry.setKeyRemovalCharge(curveId, charge);

        uint256 chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, charge);

        vm.prank(admin);
        parametersRegistry.unsetKeyRemovalCharge(curveId);

        chargeOut = parametersRegistry.getKeyRemovalCharge(curveId);

        assertEq(chargeOut, defaultInitData.keyRemovalCharge);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(chargeOut, defaultInitData.keyRemovalCharge);
    }
}

contract CSParametersRegistryElRewardsStealingAdditionalFineTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 fine = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultElRewardsStealingAdditionalFineSet(
            fine
        );
        vm.prank(admin);
        parametersRegistry.setDefaultElRewardsStealingAdditionalFine(fine);

        assertEq(
            parametersRegistry.defaultElRewardsStealingAdditionalFine(),
            fine
        );
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 fine = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultElRewardsStealingAdditionalFine(fine);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.ElRewardsStealingAdditionalFineSet(
            curveId,
            fine
        );
        vm.prank(admin);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 fine = 1 ether;

        vm.prank(admin);
        parametersRegistry.setElRewardsStealingAdditionalFine(curveId, fine);

        uint256 fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(fineOut, fine);

        vm.prank(admin);
        parametersRegistry.unsetElRewardsStealingAdditionalFine(curveId);

        fineOut = parametersRegistry.getElRewardsStealingAdditionalFine(
            curveId
        );

        assertEq(fineOut, defaultInitData.elRewardsStealingAdditionalFine);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(fineOut, defaultInitData.elRewardsStealingAdditionalFine);
    }
}

contract CSParametersRegistryKeysLimitTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 limit = 1000;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultKeysLimitSet(limit);
        vm.prank(admin);
        parametersRegistry.setDefaultKeysLimit(limit);

        assertEq(parametersRegistry.defaultKeysLimit(), limit);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 limit = 1000;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultKeysLimit(limit);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 limit = 1000;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.KeysLimitSet(curveId, limit);
        vm.prank(admin);
        parametersRegistry.setKeysLimit(curveId, limit);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 limit = 1000;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setKeysLimit(curveId, limit);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 limit = 1000;

        vm.prank(admin);
        parametersRegistry.setKeysLimit(curveId, limit);

        uint256 limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, limit);

        vm.prank(admin);
        parametersRegistry.unsetKeysLimit(curveId);

        limitOut = parametersRegistry.getKeysLimit(curveId);

        assertEq(limitOut, defaultInitData.keysLimit);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(limitOut, defaultInitData.keysLimit);
    }
}

contract CSParametersRegistryStrikesParamsTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 lifetime = 12;
        uint256 threshold = 6;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultStrikesParamsSet(lifetime, threshold);
        vm.prank(admin);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);

        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .defaultStrikesParams();

        assertEq(lifetimeOut, lifetime);
        assertEq(thresholdOut, threshold);
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

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 lifetime = 12;
        uint256 threshold = 6;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultStrikesParams(lifetime, threshold);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 lifetime = 8;
        uint256 threshold = 2;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.StrikesParamsSet(
            curveId,
            lifetime,
            threshold
        );
        vm.prank(admin);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
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

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 lifetime = 3;
        uint256 threshold = 2;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 lifetime = 3;
        uint256 threshold = 2;

        vm.prank(admin);
        parametersRegistry.setStrikesParams(curveId, lifetime, threshold);

        (uint256 lifetimeOut, uint256 thresholdOut) = parametersRegistry
            .getStrikesParams(curveId);

        assertEq(lifetimeOut, lifetime);
        assertEq(thresholdOut, threshold);

        vm.prank(admin);
        parametersRegistry.unsetStrikesParams(curveId);

        (lifetimeOut, thresholdOut) = parametersRegistry.getStrikesParams(
            curveId
        );

        assertEq(lifetimeOut, defaultInitData.strikesLifetime);
        assertEq(thresholdOut, defaultInitData.strikesThreshold);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(lifetimeOut, defaultInitData.strikesLifetime);
        assertEq(thresholdOut, defaultInitData.strikesThreshold);
    }
}

contract CSParametersRegistryBadPerformancePenaltyTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultBadPerformancePenaltySet(penalty);
        vm.prank(admin);
        parametersRegistry.setDefaultBadPerformancePenalty(penalty);

        assertEq(parametersRegistry.defaultBadPerformancePenalty(), penalty);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultBadPerformancePenalty(penalty);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.BadPerformancePenaltySet(curveId, penalty);
        vm.prank(admin);
        parametersRegistry.setBadPerformancePenalty(curveId, penalty);

        assertEq(parametersRegistry.getBadPerformancePenalty(curveId), penalty);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setBadPerformancePenalty(curveId, penalty);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 expectedPenalty = 1 ether;

        vm.prank(admin);
        parametersRegistry.setBadPerformancePenalty(curveId, expectedPenalty);

        uint256 penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, expectedPenalty);

        vm.prank(admin);
        parametersRegistry.unsetBadPerformancePenalty(curveId);

        penalty = parametersRegistry.getBadPerformancePenalty(curveId);

        assertEq(penalty, defaultInitData.badPerformancePenalty);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(penalty, defaultInitData.badPerformancePenalty);
    }
}

contract CSParametersRegistryPerformanceCoefficientsTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 attestations = 110;
        uint256 blocks = 25;
        uint256 sync = 10;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultPerformanceCoefficientsSet(
            attestations,
            blocks,
            sync
        );
        vm.prank(admin);
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

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 attestations = 110;
        uint256 blocks = 25;
        uint256 sync = 10;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
        vm.prank(admin);
        parametersRegistry.setPerformanceCoefficients(
            curveId,
            attestations,
            blocks,
            sync
        );
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 attestations = 100;
        uint256 blocks = 20;
        uint256 sync = 5;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        vm.prank(admin);
        parametersRegistry.unsetPerformanceCoefficients(curveId);

        (attestationsOut, blocksOut, syncOut) = parametersRegistry
            .getPerformanceCoefficients(curveId);

        assertEq(attestationsOut, defaultInitData.attestationsWeight);
        assertEq(blocksOut, defaultInitData.blocksWeight);
        assertEq(syncOut, defaultInitData.syncWeight);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

        assertEq(attestationsOut, defaultInitData.attestationsWeight);
        assertEq(blocksOut, defaultInitData.blocksWeight);
        assertEq(syncOut, defaultInitData.syncWeight);
    }
}

contract CSParametersRegistryQueueConfigTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultQueueConfigSet(priority, maxDeposits);
        vm.prank(admin);
        parametersRegistry.setDefaultQueueConfig(priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .defaultQueueConfig();
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);
    }

    function test_unset() public override {
        uint256 curveId = 11;
        uint32 priority = 3;
        uint32 maxDeposits = 42;

        vm.prank(admin);
        parametersRegistry.setQueueConfig(curveId, priority, maxDeposits);

        (uint256 priorityOut, uint256 maxDepositsOut) = parametersRegistry
            .getQueueConfig(curveId);
        assertEq(priorityOut, priority);
        assertEq(maxDepositsOut, maxDeposits);

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.QueueConfigUnset(curveId);
        vm.prank(admin);
        parametersRegistry.unsetQueueConfig(curveId);

        (priorityOut, maxDepositsOut) = parametersRegistry.getQueueConfig(
            curveId
        );
        assertEq(priorityOut, defaultInitData.defaultQueuePriority);
        assertEq(maxDepositsOut, defaultInitData.defaultQueueMaxDeposits);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 11;
        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
}

contract CSParametersRegistryAllowedExitDelayTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 delay = 7 days;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultAllowedExitDelaySet(delay);
        vm.prank(admin);
        parametersRegistry.setDefaultAllowedExitDelay(delay);

        assertEq(parametersRegistry.defaultAllowedExitDelay(), delay);
    }

    function test_setDefault_RevertWhen_InvalidAllowedExitDelay() public {
        uint256 delay = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidAllowedExitDelay.selector);
        vm.prank(admin);
        parametersRegistry.setDefaultAllowedExitDelay(delay);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 delay = 7 days;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultAllowedExitDelay(delay);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.AllowedExitDelaySet(curveId, delay);
        vm.prank(admin);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function test_set_RevertWhen_InvalidAllowedExitDelay() public {
        uint256 curveId = 1;
        uint256 delay = 0;

        vm.expectRevert(ICSParametersRegistry.InvalidAllowedExitDelay.selector);
        vm.prank(admin);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setAllowedExitDelay(curveId, delay);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 delay = 3 days;

        vm.prank(admin);
        parametersRegistry.setAllowedExitDelay(curveId, delay);

        uint256 delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, delay);

        vm.prank(admin);
        parametersRegistry.unsetAllowedExitDelay(curveId);

        delayOut = parametersRegistry.getAllowedExitDelay(curveId);

        assertEq(delayOut, defaultInitData.defaultAllowedExitDelay);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
}

contract CSParametersRegistryExitDelayFeeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultExitDelayFeeSet(penalty);
        vm.prank(admin);
        parametersRegistry.setDefaultExitDelayFee(penalty);

        assertEq(parametersRegistry.defaultExitDelayFee(), penalty);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultExitDelayFee(penalty);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.ExitDelayFeeSet(curveId, penalty);
        vm.prank(admin);
        parametersRegistry.setExitDelayFee(curveId, penalty);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setExitDelayFee(curveId, penalty);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 penalty = 1 ether;

        vm.prank(admin);
        parametersRegistry.setExitDelayFee(curveId, penalty);

        uint256 penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, penalty);

        vm.prank(admin);
        parametersRegistry.unsetExitDelayFee(curveId);

        penaltyOut = parametersRegistry.getExitDelayFee(curveId);

        assertEq(penaltyOut, defaultInitData.defaultExitDelayFee);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
}

contract CSParametersRegistryMaxWithdrawalRequestFeeTest is
    CSParametersRegistryBaseTestInitialized,
    ParametersTest
{
    function test_setDefault() public override {
        uint256 fee = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.DefaultMaxWithdrawalRequestFeeSet(fee);
        vm.prank(admin);
        parametersRegistry.setDefaultMaxWithdrawalRequestFee(fee);

        assertEq(parametersRegistry.defaultMaxWithdrawalRequestFee(), fee);
    }

    function test_setDefault_RevertWhen_notAdmin() public override {
        uint256 fee = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setDefaultMaxWithdrawalRequestFee(fee);
    }

    function test_set() public override {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        vm.expectEmit(address(parametersRegistry));
        emit ICSParametersRegistry.MaxWithdrawalRequestFeeSet(curveId, fee);
        vm.prank(admin);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);
    }

    function test_set_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);
    }

    function test_unset() public override {
        uint256 curveId = 1;
        uint256 fee = 1 ether;

        vm.prank(admin);
        parametersRegistry.setMaxWithdrawalRequestFee(curveId, fee);

        uint256 feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, fee);

        vm.prank(admin);
        parametersRegistry.unsetMaxWithdrawalRequestFee(curveId);

        feeOut = parametersRegistry.getMaxWithdrawalRequestFee(curveId);

        assertEq(feeOut, defaultInitData.defaultMaxWithdrawalRequestFee);
    }

    function test_unset_RevertWhen_notAdmin() public override {
        uint256 curveId = 1;

        bytes32 role = parametersRegistry.DEFAULT_ADMIN_ROLE();
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
}
