// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test, Vm } from "forge-std/Test.sol";
import { HashConsensus } from "src/lib/base-oracle/HashConsensus.sol";
import { ReportProcessorMock } from "../../../helpers/mocks/ReportProcessorMock.sol";
import { Utilities } from "../../../helpers/Utilities.sol";

contract HashConsensusBase is Test, Utilities {
    uint256 constant CONSENSUS_VERSION = 1;
    uint256 constant EPOCHS_PER_FRAME = 225;
    uint256 constant GENESIS_TIME = 100;
    uint256 constant INITIAL_EPOCH = 1;
    uint256 constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;
    uint256 constant SECONDS_PER_SLOT = 12;
    uint256 constant SLOTS_PER_EPOCH = 32;
    uint256 constant SECONDS_PER_EPOCH = SECONDS_PER_SLOT * 32;
    // uint256 constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * 32;

    HashConsensus consensus;
    ReportProcessorMock reportProcessor;

    address admin;
    address manager;
    address stranger;
    address member1;
    address member2;
    address member3;

    function setUp() public virtual {
        admin = nextAddress("admin");
        manager = nextAddress("guest");
        stranger = nextAddress("account2");
        member1 = nextAddress("member1");
        member2 = nextAddress("member2");
        member3 = nextAddress("member3");

        vm.warp(GENESIS_TIME + INITIAL_EPOCH * SECONDS_PER_EPOCH);

        reportProcessor = new ReportProcessorMock(CONSENSUS_VERSION);
        consensus = _deployHashConsensus();
        vm.startPrank(admin);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.grantRole(consensus.MANAGE_FRAME_CONFIG_ROLE(), manager);
        consensus.grantRole(
            consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(),
            manager
        );
        consensus.grantRole(consensus.MANAGE_REPORT_PROCESSOR_ROLE(), manager);
        vm.stopPrank();
    }

    function _deployHashConsensus()
        internal
        returns (HashConsensus hashConsensus)
    {
        hashConsensus = new HashConsensus({
            slotsPerEpoch: SLOTS_PER_EPOCH,
            secondsPerSlot: SECONDS_PER_SLOT,
            genesisTime: GENESIS_TIME,
            epochsPerFrame: EPOCHS_PER_FRAME,
            fastLaneLengthSlots: INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin: admin,
            reportProcessor: address(reportProcessor)
        });
    }
}

contract HashConsensusTestAccessControl is HashConsensusBase {
    function test_updateInitialEpoch_RevertsWithoutAdminRole() public {
        bytes32 adminRole = consensus.DEFAULT_ADMIN_ROLE();
        bytes32 role = consensus.MANAGE_FRAME_CONFIG_ROLE();
        vm.prank(manager);
        expectRoleRevert(manager, adminRole);
        consensus.updateInitialEpoch(10);

        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        expectRoleRevert(stranger, adminRole);
        consensus.updateInitialEpoch(10);
    }

    function test_addMember_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.addMember(member1, 2);
    }

    function test_removeMember_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.removeMember(member1, 2);
    }

    function test_removeMember_AllowsWithManageRole() public {
        bytes32 role = consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        consensus.addMember(member1, 2);

        vm.prank(stranger);
        consensus.removeMember(member1, 1);
        assertFalse(consensus.getIsMember(member1));
        assertEq(consensus.getQuorum(), 1);
    }

    function test_setQuorum_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.setQuorum(1);
    }

    function test_disableConsensus_RevertsWithoutDisableRole() public {
        bytes32 role = consensus.DISABLE_CONSENSUS_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.disableConsensus();
    }

    function test_disableConsensus() public {
        bytes32 role = consensus.DISABLE_CONSENSUS_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        consensus.disableConsensus();

        assertEq(consensus.getQuorum(), type(uint256).max);
    }

    function test_setFrameConfig_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_FRAME_CONFIG_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.setFrameConfig(5, 0);
    }

    function test_setReportProcessor_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_REPORT_PROCESSOR_ROLE();
        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.setReportProcessor(address(newReportProcessor));
    }

    function test_setFastLaneLengthSlots_RevertsWithoutManageRole() public {
        bytes32 role = consensus.MANAGE_FAST_LANE_CONFIG_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        consensus.setFastLaneLengthSlots(5);
    }
}

contract HashConsensusTestDeploy is HashConsensusBase {
    function test_getChainConfig() public view {
        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = consensus.getChainConfig();
        assertEq(slotsPerEpoch, SLOTS_PER_EPOCH);
        assertEq(secondsPerSlot, SECONDS_PER_SLOT);
        assertEq(genesisTime, GENESIS_TIME);
    }

    function test_getFrameConfig() public view {
        (
            uint256 initialEpoch,
            uint256 epochsPerFrame,
            uint256 fastLaneLengthSlots
        ) = consensus.getFrameConfig();
        assertEq(initialEpoch, INITIAL_EPOCH);
        assertEq(epochsPerFrame, EPOCHS_PER_FRAME);
        assertEq(fastLaneLengthSlots, INITIAL_FAST_LANE_LENGTH_SLOTS);
    }

    function test_constructor_RevertIfReportProcessorIsZero() public {
        vm.expectRevert(HashConsensus.ReportProcessorCannotBeZero.selector);
        new HashConsensus({
            slotsPerEpoch: SLOTS_PER_EPOCH,
            secondsPerSlot: SECONDS_PER_SLOT,
            genesisTime: GENESIS_TIME,
            epochsPerFrame: EPOCHS_PER_FRAME,
            fastLaneLengthSlots: INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin: admin,
            reportProcessor: address(0)
        });
    }

    function test_constructor_RevertIfAdminAddressIsZero() public {
        vm.expectRevert(HashConsensus.AdminCannotBeZero.selector);
        new HashConsensus({
            slotsPerEpoch: SLOTS_PER_EPOCH,
            secondsPerSlot: SECONDS_PER_SLOT,
            genesisTime: GENESIS_TIME,
            epochsPerFrame: EPOCHS_PER_FRAME,
            fastLaneLengthSlots: INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin: address(0),
            reportProcessor: address(reportProcessor)
        });
    }

    function test_constructor_RevertIfSlotsPerEpochIsZero() public {
        vm.expectRevert(HashConsensus.InvalidChainConfig.selector);
        new HashConsensus({
            slotsPerEpoch: 0,
            secondsPerSlot: SECONDS_PER_SLOT,
            genesisTime: GENESIS_TIME,
            epochsPerFrame: EPOCHS_PER_FRAME,
            fastLaneLengthSlots: INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin: admin,
            reportProcessor: address(reportProcessor)
        });
    }

    function test_constructor_RevertIfSecondsPerSlotIsZero() public {
        vm.expectRevert(HashConsensus.InvalidChainConfig.selector);
        new HashConsensus({
            slotsPerEpoch: SLOTS_PER_EPOCH,
            secondsPerSlot: 0,
            genesisTime: GENESIS_TIME,
            epochsPerFrame: EPOCHS_PER_FRAME,
            fastLaneLengthSlots: INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin: admin,
            reportProcessor: address(reportProcessor)
        });
    }
}

contract HashConsensusSetFastLaneLengthSlotsTest is HashConsensusBase {
    function test_setFastLaneLengthSlots() public {
        bytes32 role = consensus.MANAGE_FAST_LANE_CONFIG_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        vm.expectEmit(address(consensus));
        emit HashConsensus.FastLaneConfigSet(64);
        consensus.setFastLaneLengthSlots(64);

        (, , uint256 fastLaneLengthSlots) = consensus.getFrameConfig();
        assertEq(fastLaneLengthSlots, 64);
    }

    function test_setFastLaneLengthSlots_RevertIfFastLaneLengthSlotsGreaterThanFrame()
        public
    {
        bytes32 role = consensus.MANAGE_FAST_LANE_CONFIG_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        uint256 fastLaneLengthSlots = (EPOCHS_PER_FRAME * SLOTS_PER_EPOCH) + 1;
        vm.prank(stranger);
        vm.expectRevert(
            HashConsensus.FastLanePeriodCannotBeLongerThanFrame.selector
        );
        consensus.setFastLaneLengthSlots(fastLaneLengthSlots);
    }

    function test_setFastLaneLengthSlots_NoEmitIfSameValue() public {
        bytes32 role = consensus.MANAGE_FAST_LANE_CONFIG_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        vm.recordLogs();
        consensus.setFastLaneLengthSlots(INITIAL_FAST_LANE_LENGTH_SLOTS);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }
}

contract HashConsensusFastLaneMembersTest is HashConsensusBase {
    function test_initialState() public view {
        assertFalse(consensus.getIsFastLaneMember(member1));
        assertFalse(consensus.getConsensusStateForMember(member1).isFastLane);
        assertFalse(consensus.getIsFastLaneMember(member2));
        assertFalse(consensus.getConsensusStateForMember(member2).isFastLane);
        assertFalse(consensus.getIsFastLaneMember(member3));
        assertFalse(consensus.getConsensusStateForMember(member3).isFastLane);

        (address[] memory fastLaneMembers, ) = consensus.getFastLaneMembers();
        assertEq(fastLaneMembers.length, 0);
    }

    function test_addFastLaneMember_updatesList() public {
        vm.prank(manager);
        consensus.setFrameConfig(EPOCHS_PER_FRAME, 1);

        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        vm.stopPrank();

        (address[] memory membersBefore, ) = consensus.getFastLaneMembers();
        assertEq(membersBefore.length, 2);
        assertEq(membersBefore[0], member1);
        assertEq(membersBefore[1], member2);

        vm.prank(manager);
        consensus.addMember(member3, 3);

        (address[] memory membersAfter, ) = consensus.getFastLaneMembers();
        assertEq(membersAfter.length, 3);
        assertEq(membersAfter[0], member1);
        assertEq(membersAfter[1], member2);
        assertEq(membersAfter[2], member3);

        assertTrue(consensus.getIsFastLaneMember(member3));
        assertTrue(consensus.getConsensusStateForMember(member3).isFastLane);
    }

    function test_removeFastLaneMember_updatesList() public {
        vm.prank(manager);
        consensus.setFrameConfig(EPOCHS_PER_FRAME, 1);

        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        consensus.addMember(member3, 3);
        vm.stopPrank();

        (address[] memory membersBefore, ) = consensus.getFastLaneMembers();
        assertEq(membersBefore.length, 3);

        vm.prank(manager);
        consensus.removeMember(member1, 2);

        (address[] memory membersAfter, ) = consensus.getFastLaneMembers();
        assertEq(membersAfter.length, 2);
        assertEq(membersAfter[0], member3);
        assertEq(membersAfter[1], member2);
        assertFalse(consensus.getIsFastLaneMember(member1));
        assertFalse(consensus.getConsensusStateForMember(member1).isFastLane);
    }
}

contract HashConsensusFrameConfigTest is HashConsensusBase {
    function test_setFrameConfig() public {
        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.FrameConfigSet(INITIAL_EPOCH, 5);
        vm.expectEmit(address(consensus));
        emit HashConsensus.FastLaneConfigSet(1);
        consensus.setFrameConfig(5, 1);

        (, uint256 epochsPerFrame, ) = consensus.getFrameConfig();
        assertEq(epochsPerFrame, 5);
    }

    function test_setFrameConfig_NoEventsIfSameValues() public {
        vm.prank(manager);
        vm.recordLogs();
        consensus.setFrameConfig(
            EPOCHS_PER_FRAME,
            INITIAL_FAST_LANE_LENGTH_SLOTS
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_setFrameConfig_RevertIfEpochsPerFrameZero() public {
        vm.prank(manager);
        vm.expectRevert(HashConsensus.EpochsPerFrameCannotBeZero.selector);
        consensus.setFrameConfig(0, 0);
    }

    function test_setFrameConfig_RevertIfFastLaneLengthSlotsLongerThanFrame()
        public
    {
        vm.prank(manager);
        vm.expectRevert(
            HashConsensus.FastLanePeriodCannotBeLongerThanFrame.selector
        );
        consensus.setFrameConfig(1, 50);
    }

    function test_setFrameConfig_RevertIfCurrentEpochLessThanInitialEpoch()
        public
    {
        vm.warp(
            GENESIS_TIME +
                INITIAL_EPOCH *
                SLOTS_PER_EPOCH *
                SECONDS_PER_SLOT -
                1
        );
        vm.prank(manager);
        vm.expectRevert(HashConsensus.InitialEpochIsYetToArrive.selector);
        consensus.setFrameConfig(1, 50);
    }
}

contract HashConsensusInitialEpochTest is HashConsensusBase {
    function test_constructor_defaultInitialEpoch() public {
        consensus = _deployHashConsensus();
        uint256 maxEpoch = (type(uint64).max - GENESIS_TIME) /
            SECONDS_PER_SLOT /
            SLOTS_PER_EPOCH;
        (uint256 initialEpoch, , ) = consensus.getFrameConfig();
        assertEq(initialEpoch, maxEpoch);
        assertEq(consensus.getInitialRefSlot(), maxEpoch * SLOTS_PER_EPOCH - 1);
    }

    function test_updateInitialEpoch() public {
        consensus = _deployHashConsensus();

        vm.prank(admin);
        vm.expectEmit(address(consensus));
        emit HashConsensus.FrameConfigSet(10, EPOCHS_PER_FRAME);
        consensus.updateInitialEpoch(10);

        (uint256 initialEpoch, , ) = consensus.getFrameConfig();
        assertEq(initialEpoch, 10);

        uint256 initialRefSlot = consensus.getInitialRefSlot();
        assertEq(initialRefSlot, 10 * SLOTS_PER_EPOCH - 1);
    }

    function test_updateInitialEpoch_RevertIfInitialRefSlotLessThanProcessingSlot()
        public
    {
        vm.warp(
            GENESIS_TIME +
                INITIAL_EPOCH *
                SLOTS_PER_EPOCH *
                SECONDS_PER_SLOT -
                1
        );
        reportProcessor.setLastProcessingStartedRefSlot(
            INITIAL_EPOCH * SLOTS_PER_EPOCH
        );

        vm.prank(admin);
        vm.expectRevert(
            HashConsensus
                .InitialEpochRefSlotCannotBeEarlierThanProcessingSlot
                .selector
        );
        consensus.updateInitialEpoch(INITIAL_EPOCH);
    }

    function test_beforeInitialEpochMembersCanBeAddedAndQuorumChanged() public {
        vm.warp(
            GENESIS_TIME +
                INITIAL_EPOCH *
                SLOTS_PER_EPOCH *
                SECONDS_PER_SLOT -
                1
        );

        vm.startPrank(manager);
        consensus.addMember(member3, 1);
        assertTrue(consensus.getIsMember(member3));
        assertEq(consensus.getQuorum(), 1);

        consensus.removeMember(member3, 2);
        assertFalse(consensus.getIsMember(member3));
        assertEq(consensus.getQuorum(), 2);

        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        consensus.addMember(member3, 2);
        assertEq(consensus.getQuorum(), 2);

        consensus.setQuorum(4);
        assertEq(consensus.getQuorum(), 4);

        consensus.setQuorum(3);
        assertEq(consensus.getQuorum(), 3);

        consensus.removeMember(member3, 3);

        assertTrue(consensus.getIsMember(member1));
        assertTrue(consensus.getIsMember(member2));
        assertFalse(consensus.getIsMember(member3));
        assertEq(consensus.getQuorum(), 3);

        assertFalse(consensus.getIsMember(admin));

        (
            address[] memory addresses,
            uint256[] memory lastReportedRefSlots
        ) = consensus.getMembers();
        assertEq(addresses.length, 2);
        assertEq(lastReportedRefSlots[0], 0);
        assertEq(lastReportedRefSlots[1], 0);
    }

    function test_RevertsBeforeInitialEpoch() public {
        vm.warp(
            GENESIS_TIME +
                INITIAL_EPOCH *
                SLOTS_PER_EPOCH *
                SECONDS_PER_SLOT -
                1
        );
        vm.prank(manager);
        consensus.addMember(member1, 1);

        vm.expectRevert(HashConsensus.InitialEpochIsYetToArrive.selector);
        consensus.getCurrentFrame();

        vm.expectRevert(HashConsensus.InitialEpochIsYetToArrive.selector);
        consensus.getConsensusState();

        vm.expectRevert(HashConsensus.InitialEpochIsYetToArrive.selector);
        consensus.getConsensusStateForMember(member1);

        uint256 firstRefSlot = INITIAL_EPOCH * SLOTS_PER_EPOCH - 1;
        vm.expectRevert(HashConsensus.InitialEpochIsYetToArrive.selector);
        vm.prank(member1);
        consensus.submitReport(
            firstRefSlot,
            keccak256("HASH_1"),
            CONSENSUS_VERSION
        );
    }

    function test_afterInitialEpoch() public {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.setQuorum(2);
        vm.stopPrank();
        assertEq(consensus.getQuorum(), 2);

        (uint256 refSlot, uint256 deadline) = consensus.getCurrentFrame();
        assertEq(refSlot, INITIAL_EPOCH * SLOTS_PER_EPOCH - 1);
        assertEq(
            deadline,
            INITIAL_EPOCH *
                SLOTS_PER_EPOCH +
                EPOCHS_PER_FRAME *
                SLOTS_PER_EPOCH -
                1
        );

        (, bytes32 consensusReport, ) = consensus.getConsensusState();
        assertEq(consensusReport, bytes32(0));

        HashConsensus.MemberConsensusState memory memberState = consensus
            .getConsensusStateForMember(member1);
        assertTrue(memberState.isMember);
        assertEq(memberState.currentFrameRefSlot, refSlot);
        assertEq(memberState.lastMemberReportRefSlot, 0);

        vm.prank(member1);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ReportReceived(
            refSlot,
            member1,
            keccak256("HASH_1")
        );
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
    }

    function test_updateInitialEpoch_RevertIfInitialEpochAlreadyArrived()
        public
    {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.prank(admin);
        vm.expectRevert(HashConsensus.InitialEpochAlreadyArrived.selector);
        consensus.updateInitialEpoch(INITIAL_EPOCH + 1);

        vm.prank(admin);
        vm.expectRevert(HashConsensus.InitialEpochAlreadyArrived.selector);
        consensus.updateInitialEpoch(INITIAL_EPOCH - 1);
    }

    function test_crossingFrameBoundaryTimeAdvancesReferenceAndDeadlineSlotsByTheFrameSize()
        public
    {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.startPrank(manager);
        consensus.setFrameConfig(5, 0);
        vm.stopPrank();

        vm.warp(GENESIS_TIME + 11 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT - 1);

        (uint256 refSlot, uint256 deadline) = consensus.getCurrentFrame();
        assertEq(refSlot, 6 * SLOTS_PER_EPOCH - 1);
        assertEq(deadline, 11 * SLOTS_PER_EPOCH - 1);

        vm.warp(GENESIS_TIME + 11 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        (uint256 newRefSlot, uint256 newDeadline) = consensus.getCurrentFrame();
        assertEq(newRefSlot, 11 * SLOTS_PER_EPOCH - 1);
        assertEq(newDeadline, 16 * SLOTS_PER_EPOCH - 1);
    }

    function test_increasingFrameSizeAlwaysKeepsTheCurrentStartSlot() public {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.startPrank(manager);
        consensus.setFrameConfig(5, 0);
        vm.stopPrank();

        vm.warp(GENESIS_TIME + 11 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT - 1);

        (uint256 refSlot, uint256 deadline) = consensus.getCurrentFrame();
        assertEq(refSlot, 6 * SLOTS_PER_EPOCH - 1);
        assertEq(deadline, 11 * SLOTS_PER_EPOCH - 1);

        vm.warp(GENESIS_TIME + 11 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        (uint256 newRefSlot, uint256 newDeadline) = consensus.getCurrentFrame();
        assertEq(newRefSlot, 11 * SLOTS_PER_EPOCH - 1);
        assertEq(newDeadline, 16 * SLOTS_PER_EPOCH - 1);

        vm.startPrank(manager);
        consensus.setFrameConfig(7, 0);
        vm.stopPrank();

        (uint256 newRefSlot2, uint256 newDeadline2) = consensus
            .getCurrentFrame();
        assertEq(newRefSlot2, 11 * SLOTS_PER_EPOCH - 1);
        assertEq(newDeadline2, 18 * SLOTS_PER_EPOCH - 1);
    }

    function test_decreasingFrameSizeCannotDecreaseTheCurrentReferenceSlot()
        public
    {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.startPrank(manager);
        consensus.setFrameConfig(5, 0);
        vm.stopPrank();

        vm.warp(GENESIS_TIME + 7 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        (uint256 refSlot, uint256 deadline) = consensus.getCurrentFrame();
        assertEq(refSlot, 6 * SLOTS_PER_EPOCH - 1);
        assertEq(deadline, 11 * SLOTS_PER_EPOCH - 1);

        vm.startPrank(manager);
        consensus.setFrameConfig(4, 0);
        vm.stopPrank();

        (uint256 newRefSlot, uint256 newDeadline) = consensus.getCurrentFrame();
        assertEq(newRefSlot, 6 * SLOTS_PER_EPOCH - 1);
        assertEq(newDeadline, 10 * SLOTS_PER_EPOCH - 1);
    }

    function test_decreasingFrameSizeMayAdvanceTheCurrentReferenceSlotButAtLeastByTheNewFrameSize()
        public
    {
        vm.warp(
            GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT
        );
        vm.startPrank(manager);
        consensus.setFrameConfig(5, 0);
        vm.stopPrank();

        vm.warp(GENESIS_TIME + 10 * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        (uint256 refSlot, uint256 deadline) = consensus.getCurrentFrame();
        assertEq(refSlot, 6 * SLOTS_PER_EPOCH - 1);
        assertEq(deadline, 11 * SLOTS_PER_EPOCH - 1);

        vm.startPrank(manager);
        consensus.setFrameConfig(4, 0);
        vm.stopPrank();

        (uint256 newRefSlot, uint256 newDeadline) = consensus.getCurrentFrame();
        assertEq(newRefSlot, 10 * SLOTS_PER_EPOCH - 1);
        assertEq(newDeadline, 14 * SLOTS_PER_EPOCH - 1);
    }
}

contract HashConsensusAddMembersTest is HashConsensusBase {
    function test_addMember_RevertIfMemberAddressZero() public {
        vm.prank(manager);
        vm.expectRevert(HashConsensus.AddressCannotBeZero.selector);
        consensus.addMember(address(0), 1);
    }

    function test_addMember_RevertIfQuorumIsZero() public {
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(HashConsensus.QuorumTooSmall.selector, 1, 0)
        );
        consensus.addMember(member1, 0);
    }

    function test_addMember_RevertIfMemberAlreadyAdded() public {
        vm.prank(manager);
        consensus.addMember(member1, 2);

        vm.prank(manager);
        vm.expectRevert(HashConsensus.DuplicateMember.selector);
        consensus.addMember(member1, 2);
    }

    function test_addMember_RevertIfQuorumLessThanHalfOfTotalMembers() public {
        vm.prank(manager);
        consensus.addMember(member1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(HashConsensus.QuorumTooSmall.selector, 2, 1)
        );
        vm.prank(manager);
        consensus.addMember(member2, 1);
    }

    function test_addMember() public {
        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.MemberAdded(member1, 1, 1);
        consensus.addMember(member1, 1);

        assertTrue(consensus.getIsMember(member1));

        (
            address[] memory addresses,
            uint256[] memory lastReportedRefSlots
        ) = consensus.getMembers();
        assertEq(addresses.length, 1);
        assertEq(lastReportedRefSlots[0], 0);

        HashConsensus.MemberConsensusState memory memberState = consensus
            .getConsensusStateForMember(member1);
        assertTrue(memberState.isMember);
        assertTrue(memberState.canReport);
        assertEq(memberState.lastMemberReportRefSlot, 0);
        assertEq(memberState.currentFrameMemberReport, bytes32(0));

        assertEq(consensus.getQuorum(), 1);
    }

    function test_addMember_AllowsSettingQuorumMoreThanTotalMembersCount()
        public
    {
        vm.prank(manager);
        consensus.addMember(member1, 1);

        vm.expectEmit(address(consensus));
        emit HashConsensus.MemberAdded(member2, 2, 3);
        vm.prank(manager);
        consensus.addMember(member2, 3);

        assertTrue(consensus.getIsMember(member2));
        assertEq(consensus.getQuorum(), 3);
    }

    function test_addMember_lowerQuorumTriggerConsensus() public {
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 3);
        vm.stopPrank();

        (uint256 refSlot, ) = consensus.getCurrentFrame();

        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        (, bytes32 consensusReport, ) = consensus.getConsensusState();
        assertEq(consensusReport, bytes32(0));

        vm.expectEmit(address(consensus));
        emit HashConsensus.MemberAdded(member3, 3, 2);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusReached(refSlot, keccak256("HASH_1"), 2);
        vm.prank(manager);
        consensus.addMember(member3, 2);

        (, bytes32 newConsensusReport, ) = consensus.getConsensusState();
        assertEq(newConsensusReport, keccak256("HASH_1"));
    }

    function test_addMember_higherQuorumTriggerConsensusLoss() public {
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        vm.stopPrank();

        (uint256 refSlot, ) = consensus.getCurrentFrame();

        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        (, bytes32 consensusReport, ) = consensus.getConsensusState();
        assertEq(consensusReport, keccak256("HASH_1"));

        vm.expectEmit(address(consensus));
        emit HashConsensus.MemberAdded(member3, 3, 3);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusLost(refSlot);
        vm.prank(manager);
        consensus.addMember(member3, 3);

        (, bytes32 newConsensusReport, ) = consensus.getConsensusState();
        assertEq(newConsensusReport, bytes32(0));
    }
}

contract HashConsensusRemoveMemberTest is HashConsensusBase {
    function setUp() public override {
        super.setUp();
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        consensus.addMember(member3, 3);
        vm.stopPrank();
    }

    function test_removeMember_RevertIfMemberNotAdded() public {
        vm.prank(manager);
        vm.expectRevert(HashConsensus.NonMember.selector);
        consensus.removeMember(stranger, 4);
    }

    function test_removeMember_RevertIfMemberAlreadyRemoved() public {
        vm.prank(manager);
        consensus.removeMember(member1, 4);

        vm.prank(manager);
        vm.expectRevert(HashConsensus.NonMember.selector);
        consensus.removeMember(member1, 4);
    }

    function test_removeMember() public {
        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.MemberRemoved(member1, 2, 3);
        consensus.removeMember(member1, 3);

        assertFalse(consensus.getIsMember(member1));
        assertEq(consensus.getQuorum(), 3);

        HashConsensus.MemberConsensusState memory memberState = consensus
            .getConsensusStateForMember(member1);
        assertFalse(memberState.isMember);
        assertEq(memberState.lastMemberReportRefSlot, 0);
        assertEq(memberState.currentFrameMemberReport, bytes32(0));
    }

    function test_removeMember_canRemoveAllMembers() public {
        vm.prank(manager);
        consensus.removeMember(member1, 3);
        assertEq(consensus.getQuorum(), 3);
        assertFalse(consensus.getIsMember(member1));
        assertTrue(consensus.getIsMember(member2));
        assertTrue(consensus.getIsMember(member3));

        vm.prank(manager);
        consensus.removeMember(member2, 2);
        assertEq(consensus.getQuorum(), 2);
        assertFalse(consensus.getIsMember(member1));
        assertFalse(consensus.getIsMember(member2));
        assertTrue(consensus.getIsMember(member3));

        vm.prank(manager);
        consensus.removeMember(member3, 1);
        assertEq(consensus.getQuorum(), 1);
        assertFalse(consensus.getIsMember(member1));
        assertFalse(consensus.getIsMember(member2));
        assertFalse(consensus.getIsMember(member3));
    }

    function test_removeMember_doesNotDecreaseReportVariantsSupportIfMemberDidNotVote()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);

        (bytes32[] memory variants, uint256[] memory support) = consensus
            .getReportVariants();
        assertEq(variants.length, 2);
        assertEq(support.length, 2);
        assertTrue(variants[0] == keccak256("HASH_1"));
        assertTrue(variants[1] == keccak256("HASH_2"));
        assertEq(support[0], 1);
        assertEq(support[1], 1);

        vm.prank(manager);
        consensus.removeMember(member3, 3);

        (bytes32[] memory newVariants, uint256[] memory newSupport) = consensus
            .getReportVariants();
        assertEq(newVariants.length, 2);
        assertEq(newSupport.length, 2);
        assertTrue(newVariants[0] == keccak256("HASH_1"));
        assertTrue(newVariants[1] == keccak256("HASH_2"));
        assertEq(newSupport[0], 1);
        assertEq(newSupport[1], 1);
    }

    function test_removeMember_canTriggerConsensusIfMemberDidNotVote() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusReached(refSlot, keccak256("HASH_1"), 2);
        consensus.removeMember(member3, 2);

        (, bytes32 newConsensusReport, ) = consensus.getConsensusState();
        assertEq(newConsensusReport, keccak256("HASH_1"));
    }

    function test_removeMember_decreasesVotedVariantsSupport() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);
        vm.prank(member3);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);

        (bytes32[] memory variants, uint256[] memory support) = consensus
            .getReportVariants();
        assertEq(variants.length, 2);
        assertEq(support.length, 2);
        assertTrue(variants[0] == keccak256("HASH_1"));
        assertTrue(variants[1] == keccak256("HASH_2"));
        assertEq(support[0], 1);
        assertEq(support[1], 2);

        vm.prank(manager);
        consensus.removeMember(member3, 2);

        (bytes32[] memory newVariants, uint256[] memory newSupport) = consensus
            .getReportVariants();
        assertEq(newVariants.length, 2);
        assertEq(newSupport.length, 2);
        assertTrue(newVariants[0] == keccak256("HASH_1"));
        assertTrue(newVariants[1] == keccak256("HASH_2"));
        assertEq(newSupport[0], 1);
        assertEq(newSupport[1], 1);

        (, bytes32 consensusReport, ) = consensus.getConsensusState();
        assertEq(consensusReport, bytes32(0));
    }

    function test_removeMember_canTriggerConsensusLossIfMemberVoted() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member3);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusReached(refSlot, keccak256("HASH_1"), 3);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusLost(refSlot);
        consensus.removeMember(member3, 3);

        (, bytes32 newConsensusReport, ) = consensus.getConsensusState();
        assertEq(newConsensusReport, bytes32(0));
    }

    function test_removeMember_removeTheOnlyVoterForVariant() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);
        vm.prank(member3);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);

        (bytes32[] memory variants, uint256[] memory support) = consensus
            .getReportVariants();
        assertEq(variants.length, 2);
        assertEq(support.length, 2);
        assertTrue(variants[0] == keccak256("HASH_1"));
        assertTrue(variants[1] == keccak256("HASH_2"));
        assertEq(support[0], 1);
        assertEq(support[1], 2);

        vm.prank(manager);
        consensus.removeMember(member1, 3);

        (bytes32[] memory newVariants, uint256[] memory newSupport) = consensus
            .getReportVariants();
        assertEq(newVariants.length, 2);
        assertEq(newSupport.length, 2);
        assertTrue(newVariants[0] == keccak256("HASH_1"));
        assertTrue(newVariants[1] == keccak256("HASH_2"));
        assertEq(newSupport[0], 0);
        assertEq(newSupport[1], 2);

        (, bytes32 consensusReport, ) = consensus.getConsensusState();
        assertEq(consensusReport, bytes32(0));
    }
    // no tests for "Re-triggering consensus via members and quorum manipulation" as it seems to be covered already
}

contract HashConsensusReportProcessorTest is HashConsensusBase {
    function test_setReportProcessor_RevertIfReportProcessorIsZero() public {
        vm.prank(manager);
        vm.expectRevert(HashConsensus.ReportProcessorCannotBeZero.selector);
        consensus.setReportProcessor(address(0));
    }

    function test_setReportProcessor_RevertIfReportProcessorIsTheSame() public {
        vm.prank(manager);
        vm.expectRevert(HashConsensus.NewProcessorCannotBeTheSame.selector);
        consensus.setReportProcessor(address(reportProcessor));
    }

    function test_setReportProcessor() public {
        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(manager);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ReportProcessorSet(
            address(newReportProcessor),
            address(reportProcessor)
        );
        consensus.setReportProcessor(address(newReportProcessor));

        assertEq(consensus.getReportProcessor(), address(newReportProcessor));
    }

    function test_setReportProcessor_submitReportToNewProcessorIfNotProcessedYet()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(manager);
        consensus.addMember(member1, 1);
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(manager);
        consensus.setReportProcessor(address(newReportProcessor));

        assertEq(newReportProcessor.getLastCall_submitReport().callCount, 1);
    }

    function test_setReportProcessor_doNotSubmitReportToNewProcessorIfAlreadyProcessed()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(manager);
        consensus.addMember(member1, 1);
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(address(reportProcessor));
        reportProcessor.startReportProcessing();

        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(manager);
        consensus.setReportProcessor(address(newReportProcessor));

        assertEq(newReportProcessor.getLastCall_submitReport().callCount, 0);
    }

    function test_setReportProcessor_doNotSubmitReportToNewProcessorIfAlreadyProcessedForCurrentFrame()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(manager);
        consensus.addMember(member1, 1);
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(address(reportProcessor));
        reportProcessor.setLastProcessingStartedRefSlot(refSlot);

        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(manager);
        consensus.setReportProcessor(address(newReportProcessor));

        assertEq(newReportProcessor.getLastCall_submitReport().callCount, 0);
    }

    function test_setReportProcessor_doNotSubmitReportToNewProcessorIfNoConsensus()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        consensus.addMember(member2, 2);
        vm.stopPrank();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        ReportProcessorMock newReportProcessor = new ReportProcessorMock(
            CONSENSUS_VERSION
        );
        vm.prank(manager);
        consensus.setReportProcessor(address(newReportProcessor));

        assertEq(newReportProcessor.getLastCall_submitReport().callCount, 0);
    }

    function test_getReportVariants_returnsEmptyIfInFutureFrame() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(manager);
        consensus.addMember(member1, 1);
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        (bytes32[] memory variants, uint256[] memory support) = consensus
            .getReportVariants();
        assertEq(variants.length, 1);
        assertEq(support.length, 1);
        assertTrue(variants[0] == keccak256("HASH_1"));
        assertEq(support[0], 1);

        vm.warp(
            GENESIS_TIME +
                (INITIAL_EPOCH * EPOCHS_PER_FRAME + 1) *
                SECONDS_PER_EPOCH
        );
        (variants, support) = consensus.getReportVariants();
        assertEq(variants.length, 0);
        assertEq(support.length, 0);
    }
}

contract HashConsensusSetQuorumTest is HashConsensusBase {
    // TODO tested already in the addMember tests, same logic for quorum
    // backport remaining tests from core

    function test_setQuorum() public {
        bytes32 role = consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
        vm.prank(admin);
        consensus.grantRole(role, stranger);

        vm.prank(stranger);
        consensus.setQuorum(1);

        assertEq(consensus.getQuorum(), 1);
    }
}

contract HashConsensusSubmitReportTest is HashConsensusBase {
    function setUp() public override {
        super.setUp();
        vm.startPrank(manager);
        consensus.addMember(member1, 1);
        vm.stopPrank();
    }

    function test_submitReport_RevertsIfSlotGreaterThanMaxAllowed() public {
        vm.prank(member1);
        vm.expectRevert(HashConsensus.NumericOverflow.selector);
        uint256 maxSlot = type(uint64).max;
        consensus.submitReport(
            maxSlot + 1,
            keccak256("HASH_1"),
            CONSENSUS_VERSION
        );
    }

    function test_submitReport_RevertsIfSlotIsZero() public {
        vm.prank(member1);
        vm.expectRevert(HashConsensus.InvalidSlot.selector);
        consensus.submitReport(0, keccak256("HASH_1"), CONSENSUS_VERSION);
    }

    function test_submitReport_RevertsIfNotRefSlot() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();

        vm.prank(member1);
        vm.expectRevert(HashConsensus.InvalidSlot.selector);
        consensus.submitReport(
            refSlot + 1,
            keccak256("HASH_1"),
            CONSENSUS_VERSION
        );
    }

    function test_submitReport_RevertsIfUnexpectedConsensusVersion() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                HashConsensus.UnexpectedConsensusVersion.selector,
                1,
                2
            )
        );
        consensus.submitReport(
            refSlot,
            keccak256("HASH_1"),
            CONSENSUS_VERSION + 1
        );
    }

    function test_submitReport_RevertsIfEmptyReport() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        vm.expectRevert(HashConsensus.EmptyReport.selector);
        consensus.submitReport(refSlot, bytes32(0), CONSENSUS_VERSION);
    }

    function test_submitReport_RevertsIfConsensusReportAlreadyProcessing()
        public
    {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(address(reportProcessor));
        reportProcessor.startReportProcessing();

        vm.prank(member1);
        vm.expectRevert(
            HashConsensus.ConsensusReportAlreadyProcessing.selector
        );
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);
    }

    function test_submitReport_RevertsIfDuplicateReport() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(member1);
        vm.expectRevert(HashConsensus.DuplicateReport.selector);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
    }

    function test_submitReport_IfMemberHasNotSentReportForThisSlot() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(address(reportProcessor));
        reportProcessor.startReportProcessing();

        vm.prank(manager);
        consensus.addMember(member2, 2);
        vm.prank(member2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);
    }

    function test_submitReport_ConsensusLossOnConflictingReportSubmit() public {
        (uint256 refSlot, ) = consensus.getCurrentFrame();
        vm.prank(manager);
        consensus.addMember(member2, 2);
        vm.prank(member1);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(member2);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusReached(refSlot, keccak256("HASH_1"), 2);
        consensus.submitReport(refSlot, keccak256("HASH_1"), CONSENSUS_VERSION);

        vm.prank(member2);
        vm.expectEmit(address(consensus));
        emit HashConsensus.ConsensusLost(refSlot);
        consensus.submitReport(refSlot, keccak256("HASH_2"), CONSENSUS_VERSION);
    }
}
