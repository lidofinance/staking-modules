// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { Ejector } from "src/Ejector.sol";
import { IEjector } from "src/interfaces/IEjector.sol";
import { ITriggerableWithdrawalsGateway, ValidatorData } from "src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { TWGMock } from "../helpers/mocks/TWGMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { ValidatorStrikesMock } from "../helpers/mocks/ValidatorStrikesMock.sol";

contract EjectorTestBase is Test, Utilities, Fixtures {
    Ejector internal ejector;
    CSMMock internal csm;
    ValidatorStrikesMock internal strikes;
    IAccounting internal accounting;
    TWGMock internal twg;

    address internal stranger;
    address internal admin;
    address internal refundRecipient;
    uint256 internal constant NO_ID = 0;
    uint256 internal constant STAKING_MODULE_ID = 0;

    function setUp() public {
        csm = new CSMMock();
        accounting = csm.accounting();
        strikes = new ValidatorStrikesMock();
        twg = TWGMock(
            payable(csm.LIDO_LOCATOR().triggerableWithdrawalsGateway())
        );
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");
        refundRecipient = nextAddress("refundRecipient");

        ejector = new Ejector(
            address(csm),
            address(strikes),
            STAKING_MODULE_ID,
            admin
        );
    }
}

contract EjectorTestMisc is EjectorTestBase {
    function test_constructor() public {
        ejector = new Ejector(
            address(csm),
            address(strikes),
            STAKING_MODULE_ID,
            admin
        );
        assertEq(address(ejector.MODULE()), address(csm));
        assertEq(ejector.STAKING_MODULE_ID(), STAKING_MODULE_ID);
        assertEq(ejector.STRIKES(), address(strikes));
        assertEq(ejector.getRoleMemberCount(ejector.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(ejector.getRoleMember(ejector.DEFAULT_ADMIN_ROLE(), 0), admin);
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IEjector.ZeroModuleAddress.selector);
        new Ejector(address(0), address(strikes), STAKING_MODULE_ID, admin);
    }

    function test_constructor_RevertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(IEjector.ZeroStrikesAddress.selector);
        new Ejector(address(csm), address(0), STAKING_MODULE_ID, admin);
    }

    function test_constructor_RevertWhen_ZeroAdminAddress() public {
        vm.expectRevert(IEjector.ZeroAdminAddress.selector);
        new Ejector(
            address(csm),
            address(strikes),
            STAKING_MODULE_ID,
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

    function test_recovererRole_revertWhen_noRole() public {
        bytes32 role = ejector.RECOVERER_ROLE();

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        ejector.recoverEther();

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        ejector.recoverERC20(address(1), 1);

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        ejector.recoverERC721(address(1), 1);

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        ejector.recoverERC1155(address(1), 1);
    }
}

contract EjectorTestVoluntaryEject is EjectorTestBase {
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
        expectedExitsData[0] = ValidatorData(0, NO_ID, pubkey);
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
        emit IEjector.VoluntaryEjectionRequested({
            nodeOperatorId: NO_ID,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        ejector.voluntaryEject(NO_ID, keyIndex, 1, refundRecipient);
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
            expectedExitsData[i] = ValidatorData(0, NO_ID, pubkey);
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
            emit IEjector.VoluntaryEjectionRequested({
                nodeOperatorId: NO_ID,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }
        ejector.voluntaryEject(NO_ID, keyIndex, keysCount, refundRecipient);
    }

    function test_voluntaryEject_withOffset() public {
        uint256 startFrom = 1;
        uint256 keysCount = 2;
        bytes memory pubkeys = csm.getSigningKeys(0, startFrom, keysCount);

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(3);
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
            expectedExitsData[i] = ValidatorData(0, NO_ID, pubkey);
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
            emit IEjector.VoluntaryEjectionRequested({
                nodeOperatorId: NO_ID,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }
        ejector.voluntaryEject(NO_ID, startFrom, keysCount, refundRecipient);
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
            NO_ID,
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
        ejector.voluntaryEject{ value: 1 ether }(
            NO_ID,
            keyIndex,
            1,
            address(0)
        );
        uint256 expectedRefund = (1 ether * twg.MOCK_REFUND_PERCENTAGE_BP()) /
            10000;
        assertEq(nodeOperator.balance, expectedRefund);
    }

    function test_voluntaryEject_revertWhen_NodeOperatorDoesNotExist() public {
        uint256 keyIndex = 0;

        vm.expectRevert(IEjector.NodeOperatorDoesNotExist.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
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

        vm.expectRevert(IEjector.NothingToEject.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 0, refundRecipient);
    }

    function test_voluntaryEject_revertWhen_senderIsNotEligible() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(stranger, stranger, false)
        );

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
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

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
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

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
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

        vm.expectRevert(IEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
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

        vm.expectRevert(IEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_paused() public {
        uint256 keyIndex = 0;

        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);
        ejector.pauseFor(100);
        vm.stopPrank();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, refundRecipient);
    }

    function test_voluntaryEject_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setIsValidatorWithdrawn(NO_ID, keyIndex, true);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(IEjector.AlreadyWithdrawn.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, 1, address(0));
    }

    function test_voluntaryEject_revertWhen_withdrawnKeyInsideRange() public {
        uint256 keyIndex = 0;
        uint256 keysCount = 3;

        csm.mock_setNodeOperatorTotalDepositedKeys(keysCount);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setIsValidatorWithdrawn(NO_ID, keyIndex + 2, true);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );

        vm.expectRevert(IEjector.AlreadyWithdrawn.selector);
        ejector.voluntaryEject(NO_ID, keyIndex, keysCount, refundRecipient);
    }
}

contract EjectorTestVoluntaryEjectByArray is EjectorTestBase {
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
        expectedExitsData[0] = ValidatorData(0, NO_ID, pubkey);
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
        emit IEjector.VoluntaryEjectionRequested({
            nodeOperatorId: NO_ID,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        ejector.voluntaryEjectByArray(NO_ID, indices, refundRecipient);
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
            expectedExitsData[i] = ValidatorData(0, NO_ID, pubkey);
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
            emit IEjector.VoluntaryEjectionRequested({
                nodeOperatorId: NO_ID,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }
        ejector.voluntaryEjectByArray(NO_ID, indices, refundRecipient);
    }

    function test_voluntaryEjectByArray_nonSequentialIndices() public {
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

        uint256[] memory indices = new uint256[](3);
        indices[0] = 0;
        indices[1] = 2;
        indices[2] = 4;

        ValidatorData[] memory expectedExitsData = new ValidatorData[](
            indices.length
        );
        bytes[] memory emittedPubkeys = new bytes[](indices.length);
        for (uint256 i; i < indices.length; ++i) {
            bytes memory pubkey = slice(pubkeys, 48 * indices[i], 48);
            expectedExitsData[i] = ValidatorData(0, NO_ID, pubkey);
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
        for (uint256 i; i < indices.length; ++i) {
            vm.expectEmit(address(ejector));
            emit IEjector.VoluntaryEjectionRequested({
                nodeOperatorId: NO_ID,
                pubkey: emittedPubkeys[i],
                refundRecipient: refundRecipient
            });
        }

        ejector.voluntaryEjectByArray(NO_ID, indices, refundRecipient);
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
            NO_ID,
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
            NO_ID,
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

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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
        vm.expectRevert(IEjector.NothingToEject.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, refundRecipient);
    }

    function test_voluntaryEjectByArray_revertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 keyIndex = 0;

        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(IEjector.NodeOperatorDoesNotExist.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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

        vm.expectRevert(IEjector.SenderIsNotEligible.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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

        vm.expectRevert(IEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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

        vm.expectRevert(IEjector.SigningKeysInvalidOffset.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
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
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
    }

    function test_voluntaryEjectByArray_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setNodeOperatorsCount(1);
        csm.mock_setIsValidatorWithdrawn(NO_ID, keyIndex, true);
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties(
                address(this),
                address(this),
                false
            )
        );
        uint256[] memory indices = new uint256[](1);
        indices[0] = keyIndex;

        vm.expectRevert(IEjector.AlreadyWithdrawn.selector);
        ejector.voluntaryEjectByArray(NO_ID, indices, address(0));
    }
}

contract EjectorTestEjectBadPerformer is EjectorTestBase {
    function test_ejectBadPerformer_HappyPath() public {
        uint256 keyIndex = 0;
        bytes memory pubkey = csm.getSigningKeys(0, keyIndex, 1);

        csm.mock_setNodeOperatorTotalDepositedKeys(1);

        ValidatorData[] memory expectedExitsData = new ValidatorData[](1);
        expectedExitsData[0] = ValidatorData(0, NO_ID, pubkey);
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
        emit IEjector.BadPerformerEjectionRequested({
            nodeOperatorId: NO_ID,
            pubkey: pubkey,
            refundRecipient: refundRecipient
        });
        vm.prank(address(strikes));
        ejector.ejectBadPerformer(NO_ID, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_SigningKeysInvalidOffset()
        public
    {
        uint256 keyIndex = 1;

        csm.mock_setNodeOperatorTotalDepositedKeys(0);

        vm.prank(address(strikes));
        vm.expectRevert(IEjector.SigningKeysInvalidOffset.selector);
        ejector.ejectBadPerformer(NO_ID, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_onPause() public {
        uint256 keyIndex = 0;
        vm.startPrank(admin);
        ejector.grantRole(ejector.PAUSE_ROLE(), admin);
        ejector.pauseFor(100);
        vm.stopPrank();

        vm.prank(address(strikes));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        ejector.ejectBadPerformer(NO_ID, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_notStrikes() public {
        uint256 keyIndex = 0;

        vm.prank(stranger);
        vm.expectRevert(IEjector.SenderIsNotStrikes.selector);
        ejector.ejectBadPerformer(NO_ID, keyIndex, refundRecipient);
    }

    function test_ejectBadPerformer_revertWhen_alreadyWithdrawn() public {
        uint256 keyIndex = 0;

        csm.mock_setNodeOperatorTotalDepositedKeys(1);
        csm.mock_setIsValidatorWithdrawn(NO_ID, keyIndex, true);

        vm.prank(address(strikes));
        vm.expectRevert(IEjector.AlreadyWithdrawn.selector);
        ejector.ejectBadPerformer(NO_ID, keyIndex, refundRecipient);
    }

    function test_triggerableWithdrawalsGateway() public view {
        assertEq(
            address(ejector.triggerableWithdrawalsGateway()),
            csm.LIDO_LOCATOR().triggerableWithdrawalsGateway()
        );
    }
}
