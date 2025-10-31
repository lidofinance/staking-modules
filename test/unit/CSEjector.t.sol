// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { CSEjector } from "src/CSEjector.sol";
import { ICSEjector } from "src/interfaces/ICSEjector.sol";
import { ITriggerableWithdrawalsGateway, ValidatorData } from "src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/ICSModule.sol";
import { ICSAccounting } from "src/interfaces/ICSAccounting.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { TWGMock } from "../helpers/mocks/TWGMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { CSStrikesMock } from "../helpers/mocks/CSStrikesMock.sol";

contract CSEjectorTestBase is Test, Utilities, Fixtures {
    CSEjector internal ejector;
    CSMMock internal csm;
    CSStrikesMock internal strikes;
    ICSAccounting internal accounting;
    TWGMock internal twg;

    address internal stranger;
    address internal admin;
    address internal refundRecipient;
    uint256 internal constant noId = 0;
    uint256 internal constant stakingModuleId = 0;

    function setUp() public {
        csm = new CSMMock();
        accounting = csm.accounting();
        strikes = new CSStrikesMock();
        twg = TWGMock(
            payable(csm.LIDO_LOCATOR().triggerableWithdrawalsGateway())
        );
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");
        refundRecipient = nextAddress("refundRecipient");

        ejector = new CSEjector(
            address(csm),
            address(strikes),
            stakingModuleId,
            admin
        );
    }
}

contract CSEjectorTestMisc is CSEjectorTestBase {
    function test_constructor() public {
        ejector = new CSEjector(
            address(csm),
            address(strikes),
            stakingModuleId,
            admin
        );
        assertEq(address(ejector.MODULE()), address(csm));
        assertEq(ejector.STAKING_MODULE_ID(), stakingModuleId);
        assertEq(ejector.STRIKES(), address(strikes));
        assertEq(ejector.getRoleMemberCount(ejector.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(ejector.getRoleMember(ejector.DEFAULT_ADMIN_ROLE(), 0), admin);
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(ICSEjector.ZeroModuleAddress.selector);
        new CSEjector(address(0), address(strikes), stakingModuleId, admin);
    }

    function test_constructor_RevertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(ICSEjector.ZeroStrikesAddress.selector);
        new CSEjector(address(csm), address(0), stakingModuleId, admin);
    }

    function test_constructor_RevertWhen_ZeroAdminAddress() public {
        vm.expectRevert(ICSEjector.ZeroAdminAddress.selector);
        new CSEjector(
            address(csm),
            address(strikes),
            stakingModuleId,
            address(0)
        );
    }

    function test_pauseFor() public {
        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);

        vm.expectEmit(address(ejector));
        emit PausableUntil.Paused(100);
        ejector.pauseFor(100);

        vm.stopPrank();
        assertTrue(ejector.isPaused());
    }

    function test_pauseFor_revertWhen_noRole() public {
        expectRoleRevert(admin, ejector.PAUSE_ROLE());
        vm.prank(admin);
        ejector.pauseFor(100);
    }

    function test_resume() public {
        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);
        ejector.grantRole(ejector.RESUME_ROLE(), admin);
        ejector.pauseFor(100);

        vm.expectEmit(address(ejector));
        emit PausableUntil.Resumed();
        ejector.resume();

        vm.stopPrank();
        assertFalse(ejector.isPaused());
    }

    function test_resume_revertWhen_noRole() public {
        expectRoleRevert(admin, ejector.RESUME_ROLE());
        vm.prank(admin);
        ejector.resume();
    }

    function test_recovererRole() public {
        bytes32 role = ejector.RECOVERER_ROLE();
        vm.prank(admin);
        ejector.grantRole(role, address(1337));

        vm.prank(address(1337));
        ejector.recoverEther();
    }
}

contract CSEjectorTestVoluntaryEject is CSEjectorTestBase {
    function test_voluntaryEject_HappyPath() public {
        uint256 keyIndex = 0;
        bytes memory pubkey = csm.getSigningKeys(0, 0, 1);

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        ValidatorData[] memory expectedExitsData = new ValidatorData[](1);
        expectedExitsData[0] = ValidatorData(0, noId, pubkey);
        uint256 exitType = ejector.VOLUNTARY_EXIT_TYPE_ID();

        vm.expectCall(
            address(twg),
            abi.encodeWithSelector(
                ITriggerableWithdrawalsGateway.triggerFullWithdrawals.selector,
                expectedExitsData,
                refundRecipient,
                exitType
            )
        );
        vm.expectEmit(address(ejector));
        emit ICSEjector.VoluntaryEjectionRequested({
            nodeOperatorId: noId,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        ejector.voluntaryEject(noId, keyIndex, 1, refundRecipient);
    }

    function test_voluntaryEject_multipleSequentialKeys() public {
        uint256 keyIndex = 0;
        uint256 keysCount = 5;
        bytes memory pubkeys = csm.getSigningKeys(0, 0, 5);

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(5);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        ValidatorData[] memory expectedExitsData = new ValidatorData[](
            keysCount
        );
        bytes[] memory emittedPubkeys = new bytes[](keysCount);
        for (uint256 i; i < keysCount; ++i) {
            bytes memory pubkey = slice(pubkeys, 48 * i, 48);
            expectedExitsData[i] = ValidatorData(0, noId, pubkey);
            emittedPubkeys[i] = pubkey;
        }
        uint256 exitType = ejector.VOLUNTARY_EXIT_TYPE_ID();

        vm.expectCall(
            address(twg),
            abi.encodeWithSelector(
                ITriggerableWithdrawalsGateway.triggerFullWithdrawals.selector,
                expectedExitsData,
                refundRecipient,
                exitType
            )
        );
        for (uint256 i; i < keysCount; ++i) {
            vm.expectEmit(address(ejector));
            emit ICSEjector.VoluntaryEjectionRequested({
                nodeOperatorId: noId,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }
        ejector.voluntaryEject(noId, keyIndex, keysCount, refundRecipient);
    }

    function test_voluntaryEject_refund() public {
        uint256 keyIndex = 0;
        address nodeOperator = nextAddress("nodeOperator");

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(nodeOperator, nodeOperator, false)
        );

        vm.deal(nodeOperator, 1 ether);

        vm.prank(nodeOperator);
        ejector.voluntaryEject{ value: 1 ether }(
            noId,
            keyIndex,
            1,
            nodeOperator
        );
        uint256 expectedRefund = (1 ether * twg.MOCK_REFUND_PERCENTAGE_BP()) /
            10000;
        assertEq(nodeOperator.balance, expectedRefund);
    }

    function test_voluntaryEject_refund_defaultAddress() public {
        uint256 keyIndex = 0;
        address nodeOperator = nextAddress("nodeOperator");

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(nodeOperator, nodeOperator, false)
        );

        vm.deal(nodeOperator, 1 ether);

        vm.prank(nodeOperator);
        ejector.voluntaryEject{ value: 1 ether }(noId, keyIndex, 1, address(0));
        uint256 expectedRefund = (1 ether * twg.MOCK_REFUND_PERCENTAGE_BP()) /
            10000;
        assertEq(nodeOperator.balance, expectedRefund);
    }

    function test_voluntaryEject_revertWhen_NodeOperatorDoesNotExist() public {
        uint256 keyIndex = 0;

        vm.expectRevert(ICSEjector.NodeOperatorDoesNotExist.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_NothingToEject() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(ICSEjector.NothingToEject.selector);
        ejector.voluntaryEject(noId, keyIndex, 0, refundRecipient);
    }

    function test_voluntaryEject_revertWhen_senderIsNotEligible() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(stranger, stranger, false)
        );

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_senderIsNotEligible_managerAddress()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(address(this), stranger, false)
        );

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_senderIsNotEligible_extendedManager_fromRewardAddress()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(stranger, address(this), true)
        );

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_signingKeysInvalidOffset() public {
        uint256 keyIndex = 1;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(ICSEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_signingKeysInvalidOffset_nonDepositedKey()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(0);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(ICSEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setIsValidatorWithdrawn(true);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(ICSEjector.AlreadyWithdrawn.selector);
        ejector.voluntaryEject(noId, keyIndex, 1, address(0));
    }
}

contract CSEjectorTestVoluntaryEjectByArray is CSEjectorTestBase {
    function test_voluntaryEjectByArray_SingleKey() public {
        uint256 keyIndex = 0;
        bytes memory pubkey = csm.getSigningKeys(0, 0, 1);

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        ValidatorData[] memory expectedExitsData = new ValidatorData[](1);
        expectedExitsData[0] = ValidatorData(0, noId, pubkey);
        uint256 exitType = ejector.VOLUNTARY_EXIT_TYPE_ID();

        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;
        vm.expectCall(
            address(twg),
            abi.encodeWithSelector(
                ITriggerableWithdrawalsGateway.triggerFullWithdrawals.selector,
                expectedExitsData,
                refundRecipient,
                exitType
            )
        );
        vm.expectEmit(address(ejector));
        emit ICSEjector.VoluntaryEjectionRequested({
            nodeOperatorId: noId,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        ejector.voluntaryEjectByArray(noId, indices, refundRecipient);
    }

    function test_voluntaryEjectByArray_MultipleKeys() public {
        uint256 keysCount = 5;
        bytes memory pubkeys = csm.getSigningKeys(0, 0, keysCount);

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(keysCount);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        ValidatorData[] memory expectedExitsData = new ValidatorData[](
            keysCount
        );
        bytes[] memory emittedPubkeys = new bytes[](keysCount);
        for (uint256 i; i < keysCount; ++i) {
            bytes memory pubkey = slice(pubkeys, 48 * i, 48);
            expectedExitsData[i] = ValidatorData(0, noId, pubkey);
            emittedPubkeys[i] = pubkey;
        }
        uint256 exitType = ejector.VOLUNTARY_EXIT_TYPE_ID();

        uint256[] memory indices = new uint256[](keysCount);
        for (uint256 i = 0; i < keysCount; i++) {
            indices[i] = i;
        }
        vm.expectCall(
            address(twg),
            abi.encodeWithSelector(
                ITriggerableWithdrawalsGateway.triggerFullWithdrawals.selector,
                expectedExitsData,
                refundRecipient,
                exitType
            )
        );
        for (uint256 i; i < keysCount; ++i) {
            vm.expectEmit(address(ejector));
            emit ICSEjector.VoluntaryEjectionRequested({
                nodeOperatorId: noId,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }
        ejector.voluntaryEjectByArray(noId, indices, refundRecipient);
    }

    function test_voluntaryEjectByArray_refund() public {
        uint256 keyIndex = 0;
        address nodeOperator = nextAddress("nodeOperator");

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(nodeOperator, nodeOperator, false)
        );

        vm.deal(nodeOperator, 1 ether);

        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.prank(nodeOperator);
        ejector.voluntaryEjectByArray{ value: 1 ether }(
            noId,
            indices,
            nodeOperator
        );
        uint256 expectedRefund = (1 ether * twg.MOCK_REFUND_PERCENTAGE_BP()) /
            10000;
        assertEq(nodeOperator.balance, expectedRefund);
    }

    function test_voluntaryEjectByArray_refund_defaultAddress() public {
        uint256 keyIndex = 0;
        address nodeOperator = nextAddress("nodeOperator");

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(nodeOperator, nodeOperator, false)
        );

        vm.deal(nodeOperator, 1 ether);

        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.prank(nodeOperator);
        ejector.voluntaryEjectByArray{ value: 1 ether }(
            noId,
            indices,
            address(0)
        );
        uint256 expectedRefund = (1 ether * twg.MOCK_REFUND_PERCENTAGE_BP()) /
            10000;
        assertEq(nodeOperator.balance, expectedRefund);
    }

    function test_voluntaryEjectByArray_revertWhen_senderIsNotEligible()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(stranger, stranger, false)
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_NothingToEject() public {
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        uint256[] memory indices = new uint256[](0);
        vm.expectRevert(ICSEjector.NothingToEject.selector);
        ejector.voluntaryEjectByArray(noId, indices, refundRecipient);
    }

    function test_voluntaryEjectByArray_revertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 keyIndex = 0;

        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.NodeOperatorDoesNotExist.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_senderIsNotEligible_managerAddress()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(address(this), stranger, false)
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_senderIsNotEligible_extendedManager_fromRewardAddress()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(stranger, address(this), true)
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_signingKeysInvalidOffset()
        public
    {
        uint256 keyIndex = 1;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_signingKeysInvalidOffset_nonDepositedKey()
        public
    {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(0);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_onPause() public {
        uint256 keyIndex = 0;
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);
        ejector.pauseFor(100);
        vm.stopPrank();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setIsValidatorWithdrawn(true);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(ICSEjector.AlreadyWithdrawn.selector);
        ejector.voluntaryEjectByArray(noId, indices, address(0));
    }
}

contract CSEjectorTestEjectBadPerformer is CSEjectorTestBase {
    function test_ejectBadPerformer_HappyPath() public {
        uint256 keyIndex = 0;
        bytes memory pubkey = csm.getSigningKeys(0, keyIndex, 1);

        csm.mock_setNodeOperatorTotalDepositedKeys(1);

        ValidatorData[] memory expectedExitsData = new ValidatorData[](1);
        expectedExitsData[0] = ValidatorData(0, noId, pubkey);
        uint256 exitType = ejector.STRIKES_EXIT_TYPE_ID();

        vm.expectCall(
            address(twg),
            abi.encodeWithSelector(
                ITriggerableWithdrawalsGateway.triggerFullWithdrawals.selector,
                expectedExitsData,
                refundRecipient,
                exitType
            )
        );

        vm.expectEmit(address(ejector));
        emit ICSEjector.BadPerformerEjectionRequested({
            nodeOperatorId: noId,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        vm.prank(address(strikes));
        ejector.ejectBadPerformer(noId, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_SigningKeysInvalidOffset()
        public
    {
        uint256 keyIndex = 1;

        csm.mock_setNodeOperatorTotalDepositedKeys(0);

        vm.prank(address(strikes));
        vm.expectRevert(ICSEjector.SigningKeysInvalidOffset.selector);
        ejector.ejectBadPerformer(noId, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_onPause() public {
        uint256 keyIndex = 0;
        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);
        ejector.pauseFor(100);
        vm.stopPrank();

        vm.prank(address(strikes));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        ejector.ejectBadPerformer(noId, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_notStrikes() public {
        uint256 keyIndex = 0;

        vm.prank(stranger);
        vm.expectRevert(ICSEjector.SenderIsNotStrikes.selector);
        ejector.ejectBadPerformer(noId, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setIsValidatorWithdrawn(true);

        vm.prank(address(strikes));
        vm.expectRevert(ICSEjector.AlreadyWithdrawn.selector);
        ejector.ejectBadPerformer(noId, keyIndex, refundRecipient);
    }

    function test_triggerableWithdrawalsGateway() public view {
        assertEq(
            address(ejector.triggerableWithdrawalsGateway()),
            csm.LIDO_LOCATOR().triggerableWithdrawalsGateway()
        );
    }
}
