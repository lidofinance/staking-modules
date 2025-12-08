// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Versioned } from "src/lib/utils/Versioned.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";

contract VersionedTest is Test {
    VersionedImpl impl;
    VersionedImpl consumer;

    uint256 constant INITIAL_VERSION = 0;
    uint256 constant PETRIFIED_VERSION = type(uint256).max;

    function setUp() public {
        impl = new VersionedImpl();
        consumer = VersionedImpl(
            address(
                new OssifiableProxy(address(impl), address(this), new bytes(0))
            )
        );
    }

    function test_constructor_PetrifiesImplementation() public view {
        assertEq(impl.getContractVersion(), PETRIFIED_VERSION);
    }

    function test_getContractVersionPosition_ReturnsStorageSlotPosition()
        public
        view
    {
        assertEq(
            consumer.getContractVersionPosition(),
            keccak256("lido.Versioned.contractVersion")
        );
    }

    function test_getPetrifiedVersionMark_ReturnsPetrifiedVersion()
        public
        view
    {
        assertEq(consumer.getPetrifiedVersionMark(), PETRIFIED_VERSION);
    }

    function test_checkContractVersion_PassesIfVersionsMatch() public view {
        consumer.checkContractVersion(INITIAL_VERSION);
    }

    function test_checkContractVersion_RevertsIfVersionsDoNotMatch() public {
        uint256 expectedVersion = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Versioned.UnexpectedContractVersion.selector,
                INITIAL_VERSION,
                expectedVersion
            )
        );
        consumer.checkContractVersion(expectedVersion);
    }

    function test_initializeContractVersionTo_InitializesVersion() public {
        uint256 initVersion = 1;
        consumer.initializeContractVersionTo(initVersion);
        assertEq(consumer.getContractVersion(), initVersion);
    }

    function test_initializeContractVersionTo_RevertsIfNotZero() public {
        consumer.updateContractVersion(1);
        vm.expectRevert(Versioned.NonZeroContractVersionOnInit.selector);
        consumer.initializeContractVersionTo(1);
    }

    function test_initializeContractVersionTo_RevertsIfZero() public {
        vm.expectRevert(Versioned.InvalidContractVersion.selector);
        consumer.initializeContractVersionTo(0);
    }

    function test_updateContractVersion_UpdatesIncrementally() public {
        uint256 newVersion = INITIAL_VERSION + 1;
        consumer.updateContractVersion(newVersion);
        assertEq(consumer.getContractVersion(), newVersion);
    }

    function test_updateContractVersion_RevertsIfNotIncremental() public {
        uint256 newVersion = INITIAL_VERSION + 2;
        vm.expectRevert(Versioned.InvalidContractVersionIncrement.selector);
        consumer.updateContractVersion(newVersion);
    }
}

contract VersionedImpl is Versioned {
    constructor() Versioned() {}

    function getContractVersionPosition() external pure returns (bytes32) {
        return CONTRACT_VERSION_POSITION;
    }

    function getPetrifiedVersionMark() external pure returns (uint256) {
        return PETRIFIED_VERSION_MARK;
    }

    function checkContractVersion(uint256 version) external view {
        _checkContractVersion(version);
    }

    function initializeContractVersionTo(uint256 version) external {
        _initializeContractVersionTo(version);
    }

    function updateContractVersion(uint256 newVersion) external {
        _updateContractVersion(newVersion);
    }
}
