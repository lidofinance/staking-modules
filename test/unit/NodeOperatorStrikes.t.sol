// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { NodeOperatorStrikes } from "src/NodeOperatorStrikes.sol";
import { INodeOperatorStrikes, StrikeInput, Strike, StrikeThreshold } from "src/interfaces/INodeOperatorStrikes.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { MetaRegistryMock } from "../helpers/mocks/MetaRegistryMock.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract NodeOperatorStrikesBaseTest is Test, Utilities, Fixtures {
    CuratedMock public module;
    MetaRegistryMock public metaRegistryMock;
    NodeOperatorStrikes public strikes;

    address public admin;
    address public committee;
    address public stranger;

    uint256 internal constant MAX_BP = 10_000;
    uint256 internal constant LIFETIME = 30 days;
    bytes32 internal constant CATEGORY = keccak256("performance");
    uint256 internal constant NO_ID = 0;
    string internal constant DESCRIPTION = "Operator missed attestations for two consecutive frames";

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        committee = nextAddress("COMMITTEE");
        stranger = nextAddress("STRANGER");

        module = new CuratedMock();
        module.mock_setNodeOperatorsCount(3);

        metaRegistryMock = new MetaRegistryMock();
        module.mock_setMetaRegistry(address(metaRegistryMock));

        strikes = new NodeOperatorStrikes({ module: address(module) });
        _enableInitializers(address(strikes));
        strikes.initialize(admin, _exampleThresholds());

        bytes32 committeeRole = strikes.STRIKES_COMMITTEE_ROLE();
        vm.prank(admin);
        strikes.grantRole(committeeRole, committee);
    }

    function _input(
        uint256 nodeOperatorId,
        bytes32 category,
        uint256 lifetime
    ) internal pure returns (StrikeInput memory) {
        return
            StrikeInput({
                nodeOperatorId: nodeOperatorId,
                category: category,
                lifetime: lifetime,
                description: DESCRIPTION
            });
    }

    function _exampleThresholds() internal pure returns (StrikeThreshold[] memory thresholds) {
        thresholds = new StrikeThreshold[](4);
        thresholds[0] = StrikeThreshold({ minCount: 2, reductionBP: 2_500 });
        thresholds[1] = StrikeThreshold({ minCount: 3, reductionBP: 5_000 });
        thresholds[2] = StrikeThreshold({ minCount: 4, reductionBP: 7_500 });
        thresholds[3] = StrikeThreshold({ minCount: 5, reductionBP: 10_000 });
    }

    function _setExampleThresholds() internal {
        vm.prank(admin);
        strikes.setStrikeThresholds(_exampleThresholds());
    }

    function _issue(uint256 nodeOperatorId) internal returns (uint256 strikeId) {
        vm.prank(committee);
        strikeId = strikes.issueStrike(_input(nodeOperatorId, CATEGORY, LIFETIME));
    }

    function _expectNoStrike(uint256 nodeOperatorId, uint256 strikeId) internal {
        vm.expectRevert(INodeOperatorStrikes.StrikeNotExist.selector);
        strikes.getStrike(nodeOperatorId, strikeId);
    }
}

contract NodeOperatorStrikesConstructorTest is NodeOperatorStrikesBaseTest {
    function test_constructor_SetsImmutables() public view {
        assertEq(address(strikes.MODULE()), address(module));
        assertEq(address(strikes.META_REGISTRY()), address(metaRegistryMock));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(INodeOperatorStrikes.ZeroModuleAddress.selector);
        new NodeOperatorStrikes(address(0));
    }
}

contract NodeOperatorStrikesInitializeTest is NodeOperatorStrikesBaseTest {
    function test_initialize_SetsAdmin() public view {
        assertTrue(strikes.hasRole(strikes.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_SetsThresholds() public {
        NodeOperatorStrikes s = new NodeOperatorStrikes(address(module));
        _enableInitializers(address(s));
        s.initialize(admin, _exampleThresholds());

        StrikeThreshold[] memory stored = s.getStrikeThresholds();
        assertEq(stored.length, 4);
        assertEq(stored[0].minCount, 2);
        assertEq(stored[3].reductionBP, 10_000);
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        NodeOperatorStrikes s = new NodeOperatorStrikes(address(module));
        _enableInitializers(address(s));
        vm.expectRevert(INodeOperatorStrikes.ZeroAdminAddress.selector);
        s.initialize(address(0), new StrikeThreshold[](0));
    }

    function test_initialize_RevertWhen_InvalidThresholds() public {
        NodeOperatorStrikes s = new NodeOperatorStrikes(address(module));
        _enableInitializers(address(s));

        StrikeThreshold[] memory bad = new StrikeThreshold[](1);
        bad[0] = StrikeThreshold({ minCount: 0, reductionBP: 1_000 }); // minCount 0 is invalid
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        s.initialize(admin, bad);
    }

    function test_initialize_RevertWhen_EmptyThresholds() public {
        NodeOperatorStrikes s = new NodeOperatorStrikes(address(module));
        _enableInitializers(address(s));

        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        s.initialize(admin, new StrikeThreshold[](0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        strikes.initialize(admin, new StrikeThreshold[](0));
    }
}

contract NodeOperatorStrikesIssueTest is NodeOperatorStrikesBaseTest {
    function test_issueStrike_StoresAndRefreshes() public {
        uint256 expiry = block.timestamp + LIFETIME;

        vm.expectEmit(true, true, true, true, address(strikes));
        emit INodeOperatorStrikes.StrikeIssued(NO_ID, 1, CATEGORY, expiry, DESCRIPTION);

        vm.prank(committee);
        uint256 strikeId = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME));

        assertEq(strikeId, 1);
        assertEq(strikes.getActiveStrikesCount(NO_ID), 1);

        Strike memory s = strikes.getStrike(NO_ID, 1);
        assertEq(s.id, 1);
        assertEq(s.expiry, expiry);
        assertEq(s.category, CATEGORY);
        assertEq(s.description, DESCRIPTION);

        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), 1);
        assertEq(metaRegistryMock.lastChangedBoostOperatorId(), NO_ID);
    }

    function test_issueStrike_AssignsSequentialIds() public {
        assertEq(_issue(NO_ID), 1);
        assertEq(_issue(NO_ID), 2);
        assertEq(_issue(NO_ID), 3);
        assertEq(strikes.getActiveStrikesCount(NO_ID), 3);
    }

    function test_issueStrike_RevertWhen_NotCommittee() public {
        expectRoleRevert(stranger, strikes.STRIKES_COMMITTEE_ROLE());
        vm.prank(stranger);
        strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME));
    }

    function test_issueStrike_RevertWhen_OperatorDoesNotExist() public {
        vm.expectRevert(INodeOperatorStrikes.NodeOperatorDoesNotExist.selector);
        vm.prank(committee);
        strikes.issueStrike(_input(3, CATEGORY, LIFETIME)); // count == 3, so id 3 doesn't exist
    }

    function test_issueStrike_RevertWhen_ZeroLifetime() public {
        vm.expectRevert(INodeOperatorStrikes.ZeroLifetime.selector);
        vm.prank(committee);
        strikes.issueStrike(_input(NO_ID, CATEGORY, 0));
    }

    function test_issueStrike_RevertWhen_LifetimeOverflowsUint64() public {
        uint256 hugeLifetime = type(uint64).max; // block.timestamp + this overflows uint64
        vm.expectRevert(INodeOperatorStrikes.LifetimeTooLong.selector);
        vm.prank(committee);
        strikes.issueStrike(_input(NO_ID, CATEGORY, hugeLifetime));
    }

    function test_issueStrike_RevertWhen_LifetimeOverflowsUint256() public {
        vm.expectRevert(INodeOperatorStrikes.LifetimeTooLong.selector);
        vm.prank(committee);
        strikes.issueStrike(_input(NO_ID, CATEGORY, type(uint256).max));
    }

    function test_issueStrike_AllowsMaxLengthDescription() public {
        uint256 maxLen = strikes.MAX_DESCRIPTION_LENGTH();
        StrikeInput memory input = _input(NO_ID, CATEGORY, LIFETIME);
        input.description = string(new bytes(maxLen));

        vm.prank(committee);
        uint256 id = strikes.issueStrike(input);
        assertEq(bytes(strikes.getStrike(NO_ID, id).description).length, maxLen);
    }

    function test_issueStrike_RevertWhen_DescriptionTooLong() public {
        StrikeInput memory input = _input(NO_ID, CATEGORY, LIFETIME);
        input.description = string(new bytes(strikes.MAX_DESCRIPTION_LENGTH() + 1));

        vm.expectRevert(INodeOperatorStrikes.InvalidDescription.selector);
        vm.prank(committee);
        strikes.issueStrike(input);
    }

    function test_issueStrike_RevertWhen_EmptyDescription() public {
        StrikeInput memory input = _input(NO_ID, CATEGORY, LIFETIME);
        input.description = "";

        vm.expectRevert(INodeOperatorStrikes.InvalidDescription.selector);
        vm.prank(committee);
        strikes.issueStrike(input);
    }
}

contract NodeOperatorStrikesRemoveTest is NodeOperatorStrikesBaseTest {
    function test_removeStrike_RemovesAndRefreshes() public {
        uint256 id = _issue(NO_ID);
        uint256 refreshesBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.expectEmit(true, true, true, true, address(strikes));
        emit INodeOperatorStrikes.StrikeRemoved(NO_ID, id, committee);

        vm.prank(committee);
        strikes.removeStrike(NO_ID, id);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 0);
        _expectNoStrike(NO_ID, id); // removed
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), refreshesBefore + 1);
    }

    function test_removeStrike_RevertWhen_NotCommittee() public {
        uint256 id = _issue(NO_ID);
        bytes32 role = strikes.STRIKES_COMMITTEE_ROLE();
        uint256 expiry = strikes.getStrike(NO_ID, id).expiry;

        // Even after the lifetime elapses removeStrike stays committee-only;
        // permissionless cleanup goes through removeExpiredStrikes.
        vm.warp(expiry);

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        strikes.removeStrike(NO_ID, id);
    }

    function test_removeStrike_RevertWhen_NonExistent() public {
        vm.expectRevert(INodeOperatorStrikes.StrikeNotExist.selector);
        vm.prank(committee);
        strikes.removeStrike(NO_ID, 1);
    }

    function test_removeStrike_RevertWhen_AlreadyRemoved() public {
        uint256 id = _issue(NO_ID);
        vm.prank(committee);
        strikes.removeStrike(NO_ID, id);

        vm.expectRevert(INodeOperatorStrikes.StrikeNotExist.selector);
        vm.prank(committee);
        strikes.removeStrike(NO_ID, id);
    }

    function test_strikeIds_MonotonicWithGapsAndExpiredInActive() public {
        _issue(NO_ID); // id 1
        uint256 id2 = _issue(NO_ID); // id 2
        _issue(NO_ID); // id 3
        _issue(NO_ID); // id 4

        // Remove id 2 early (committee): id 4 swaps into its slot.
        vm.prank(committee);
        strikes.removeStrike(NO_ID, id2);

        // New strikes keep incrementing past the gap — id 2 is never reused.
        uint256 id5 = _issue(NO_ID);
        assertEq(id5, 5);
        assertEq(strikes.getActiveStrikesCount(NO_ID), 4); // 1, 3, 4, 5

        // After lifetime elapses expired strikes stay in active until explicitly removed.
        vm.warp(block.timestamp + LIFETIME);
        assertEq(strikes.getActiveStrikesCount(NO_ID), 4);

        // Gap at id 2 reverts; all others are individually reachable.
        assertEq(strikes.getStrike(NO_ID, 1).id, 1);
        _expectNoStrike(NO_ID, 2); // gap
        assertEq(strikes.getStrike(NO_ID, 3).id, 3);
        assertEq(strikes.getStrike(NO_ID, 4).id, 4);
        assertEq(strikes.getStrike(NO_ID, 5).id, 5);

        // Sum of active ids is a duplicate-free witness.
        Strike[] memory active = strikes.getStrikes(NO_ID);
        assertEq(active.length, 4);
        uint256 idSum;
        for (uint256 i; i < active.length; ++i) idSum += active[i].id;
        assertEq(idSum, 1 + 3 + 4 + 5);
    }

    function test_removeStrike_SwapPopResolvesById() public {
        _issue(NO_ID); // id 1
        uint256 id2 = _issue(NO_ID);
        uint256 id3 = _issue(NO_ID);

        // Remove the first strike: the last one (id3) is swapped into its slot.
        vm.prank(committee);
        strikes.removeStrike(NO_ID, 1);

        // The swapped strike must still resolve by its id and stay removable.
        assertEq(strikes.getActiveStrikesCount(NO_ID), 2);
        assertEq(strikes.getStrike(NO_ID, id3).id, id3);
        assertEq(strikes.getStrike(NO_ID, id2).id, id2);

        vm.prank(committee);
        strikes.removeStrike(NO_ID, id3);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 1);
        assertEq(strikes.getStrike(NO_ID, id2).id, id2);
        _expectNoStrike(NO_ID, id3); // removed
    }
}

contract NodeOperatorStrikesRemoveExpiredTest is NodeOperatorStrikesBaseTest {
    /// @dev Issues four strikes: id1/id3 short-lived (LIFETIME), id2/id4 long-lived (2x LIFETIME).
    function _issueMixed() internal returns (uint256 id1, uint256 id2, uint256 id3, uint256 id4) {
        vm.startPrank(committee);
        id1 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME));
        id2 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME * 2));
        id3 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME));
        id4 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME * 2));
        vm.stopPrank();
    }

    function test_removeExpiredStrikes_AlternatingSurvivorsStayResolvable() public {
        // Alternate expiring/surviving so back-to-front swap-pop must shuffle survivors repeatedly.
        vm.startPrank(committee);
        strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME)); // id1 expire
        uint256 id2 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME * 2)); // keep
        strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME)); // id3 expire
        uint256 id4 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME * 2)); // keep
        strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME)); // id5 expire
        uint256 id6 = strikes.issueStrike(_input(NO_ID, CATEGORY, LIFETIME * 2)); // keep
        vm.stopPrank();

        vm.warp(block.timestamp + LIFETIME);
        vm.prank(stranger);
        strikes.removeExpiredStrikes(NO_ID);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 3);
        // Every survivor still resolves by its id (index stayed consistent through the shuffles).
        assertEq(strikes.getStrike(NO_ID, id2).id, id2);
        assertEq(strikes.getStrike(NO_ID, id4).id, id4);
        assertEq(strikes.getStrike(NO_ID, id6).id, id6);
        _expectNoStrike(NO_ID, 1);
        _expectNoStrike(NO_ID, 3);
        _expectNoStrike(NO_ID, 5);
    }

    function test_removeExpiredStrikes_RemovesOnlyExpired() public {
        (uint256 id1, uint256 id2, uint256 id3, uint256 id4) = _issueMixed();

        vm.warp(block.timestamp + LIFETIME); // id1, id3 expired; id2, id4 still active
        uint256 refreshesBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(stranger); // permissionless
        strikes.removeExpiredStrikes(NO_ID);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 2);
        _expectNoStrike(NO_ID, id1);
        _expectNoStrike(NO_ID, id3);
        assertEq(strikes.getStrike(NO_ID, id2).id, id2);
        assertEq(strikes.getStrike(NO_ID, id4).id, id4);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), refreshesBefore + 1); // refreshed once
    }

    function test_removeExpiredStrikes_SurvivorStaysRemovable() public {
        (, uint256 id2, , uint256 id4) = _issueMixed();

        vm.warp(block.timestamp + LIFETIME);
        vm.prank(stranger);
        strikes.removeExpiredStrikes(NO_ID);

        // A survivor stays removable by the committee (its slot was swapped during cleanup).
        vm.prank(committee);
        strikes.removeStrike(NO_ID, id2);
        assertEq(strikes.getActiveStrikesCount(NO_ID), 1);
        assertEq(strikes.getStrike(NO_ID, id4).id, id4);
    }

    function test_removeExpiredStrikes_AllExpired() public {
        _issue(NO_ID);
        _issue(NO_ID);
        _issue(NO_ID);

        vm.warp(block.timestamp + LIFETIME);
        vm.prank(stranger);
        strikes.removeExpiredStrikes(NO_ID);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 0);
    }

    function test_removeExpiredStrikes_NoopWhenNoneExpired() public {
        _issue(NO_ID);
        _issue(NO_ID);
        uint256 refreshesBefore = metaRegistryMock.notifyWeightBoostChangedCallCount();

        vm.prank(stranger);
        strikes.removeExpiredStrikes(NO_ID);

        assertEq(strikes.getActiveStrikesCount(NO_ID), 2);
        assertEq(metaRegistryMock.notifyWeightBoostChangedCallCount(), refreshesBefore); // no refresh
    }
}

contract NodeOperatorStrikesThresholdsTest is NodeOperatorStrikesBaseTest {
    function test_setStrikeThresholds_RoundTrip() public {
        StrikeThreshold[] memory thresholds = _exampleThresholds();

        vm.expectEmit(false, false, false, true, address(strikes));
        emit INodeOperatorStrikes.StrikeThresholdsSet(thresholds);

        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);

        StrikeThreshold[] memory stored = strikes.getStrikeThresholds();
        assertEq(stored.length, 4);
        assertEq(stored[0].minCount, 2);
        assertEq(stored[0].reductionBP, 2_500);
        assertEq(stored[3].minCount, 5);
        assertEq(stored[3].reductionBP, 10_000);

        // The config change is pushed to MetaRegistry so cached weights get refreshed.
        assertEq(metaRegistryMock.notifyWeightBoostProviderConfigChangedCallCount(), 1);
    }

    function test_setStrikeThresholds_Replaces() public {
        _setExampleThresholds();

        StrikeThreshold[] memory next = new StrikeThreshold[](1);
        next[0] = StrikeThreshold({ minCount: 1, reductionBP: 1_000 });
        vm.prank(admin);
        strikes.setStrikeThresholds(next);

        StrikeThreshold[] memory stored = strikes.getStrikeThresholds();
        assertEq(stored.length, 1);
        assertEq(stored[0].minCount, 1);
        assertEq(stored[0].reductionBP, 1_000);
    }

    function test_setStrikeThresholds_RevertWhen_NotAdmin() public {
        bytes32 adminRole = strikes.DEFAULT_ADMIN_ROLE();
        expectRoleRevert(stranger, adminRole);
        vm.prank(stranger);
        strikes.setStrikeThresholds(_exampleThresholds());
    }

    function test_setStrikeThresholds_RevertWhen_Empty() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](0);
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_FirstMinCountZero() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](1);
        thresholds[0] = StrikeThreshold({ minCount: 0, reductionBP: 1_000 });
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_FirstReductionZero() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](1);
        thresholds[0] = StrikeThreshold({ minCount: 1, reductionBP: 0 });
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_MinCountNotAscending() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](2);
        thresholds[0] = StrikeThreshold({ minCount: 2, reductionBP: 2_500 });
        thresholds[1] = StrikeThreshold({ minCount: 2, reductionBP: 5_000 });
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_ReductionDecreasing() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](2);
        thresholds[0] = StrikeThreshold({ minCount: 2, reductionBP: 5_000 });
        thresholds[1] = StrikeThreshold({ minCount: 3, reductionBP: 2_500 });
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_ReductionEqual() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](2);
        thresholds[0] = StrikeThreshold({ minCount: 2, reductionBP: 2_500 });
        thresholds[1] = StrikeThreshold({ minCount: 3, reductionBP: 2_500 }); // equal -> redundant band
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_ReductionAboveMaxBp() public {
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](1);
        thresholds[0] = StrikeThreshold({ minCount: 2, reductionBP: MAX_BP + 1 });
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }

    function test_setStrikeThresholds_RevertWhen_TooMany() public {
        uint256 n = strikes.MAX_THRESHOLDS() + 1;
        StrikeThreshold[] memory thresholds = new StrikeThreshold[](n);
        for (uint256 i; i < n; ++i) {
            thresholds[i] = StrikeThreshold({ minCount: i + 1, reductionBP: 0 });
        }
        vm.expectRevert(INodeOperatorStrikes.InvalidStrikeThresholds.selector);
        vm.prank(admin);
        strikes.setStrikeThresholds(thresholds);
    }
}

contract NodeOperatorStrikesWeightMultiplierTest is NodeOperatorStrikesBaseTest {
    function test_getWeightBoostMultiplierBP_StepFunction() public {
        // 0 strikes -> full weight.
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), MAX_BP);

        _issue(NO_ID); // 1 -> full weight
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), MAX_BP);

        _issue(NO_ID); // 2 -> 75%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 7_500);

        _issue(NO_ID); // 3 -> 50%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 5_000);

        _issue(NO_ID); // 4 -> 25%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 2_500);

        _issue(NO_ID); // 5 -> 0%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 0);

        _issue(NO_ID); // 6 -> still 0% (clamped to last band)
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 0);
    }

    function test_getWeightBoostMultiplierBP_IncreasesAfterRemoval() public {
        uint256 id1 = _issue(NO_ID);
        _issue(NO_ID);
        _issue(NO_ID); // 3 active -> 50%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 5_000);

        vm.prank(committee);
        strikes.removeStrike(NO_ID, id1); // 2 active -> 75%
        assertEq(strikes.getWeightBoostMultiplierBP(NO_ID), 7_500);
    }

    function test_getStrikes_ExcludesRemoved() public {
        uint256 id1 = _issue(NO_ID);
        uint256 id2 = _issue(NO_ID);
        uint256 id3 = _issue(NO_ID);

        // Remove the middle strike to check removed slots are skipped, not zero-padded.
        vm.prank(committee);
        strikes.removeStrike(NO_ID, id2);

        Strike[] memory active = strikes.getStrikes(NO_ID);
        assertEq(active.length, 2);
        assertEq(active[0].id, id1);
        assertEq(active[1].id, id3);
    }

    function test_getStrikes() public {
        uint256 t = block.timestamp;
        bytes32 catA = keccak256("late-attestations");
        bytes32 catB = keccak256("missed-proposal");

        vm.startPrank(committee);
        uint256 idA = strikes.issueStrike(
            StrikeInput({ nodeOperatorId: NO_ID, category: catA, lifetime: LIFETIME, description: "first" })
        );
        uint256 idB = strikes.issueStrike(
            StrikeInput({ nodeOperatorId: NO_ID, category: catB, lifetime: LIFETIME * 2, description: "second" })
        );
        vm.stopPrank();

        Strike[] memory active = strikes.getStrikes(NO_ID);
        assertEq(active.length, 2);

        // Each record carries its own distinct fields.
        assertEq(active[0].id, idA);
        assertEq(active[0].category, catA);
        assertEq(uint256(active[0].expiry), t + LIFETIME);
        assertEq(active[0].description, "first");

        assertEq(active[1].id, idB);
        assertEq(active[1].category, catB);
        assertEq(uint256(active[1].expiry), t + LIFETIME * 2);
        assertEq(active[1].description, "second");
    }
}
