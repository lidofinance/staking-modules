// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "../helpers/Utilities.sol";

import { CuratedGate } from "../../src/CuratedGate.sol";
import { ICuratedGate } from "../../src/interfaces/ICuratedGate.sol";
import { CuratedGateFactory } from "../../src/CuratedGateFactory.sol";
import { ICuratedGateFactory } from "../../src/interfaces/ICuratedGateFactory.sol";

import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { OperatorsDataMock } from "../helpers/mocks/OperatorsDataMock.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";

contract CuratedGateFactoryTestBase is Test, Utilities {
    CuratedGateFactory factory;
    CSMMock module;
    OperatorsDataMock data;
    address impl;
    bytes32 root;
    string cid;
    uint256 curveId;
    uint256 moduleId;

    address admin;

    function setUp() public virtual {
        admin = nextAddress("admin");
        module = new CSMMock();
        data = new OperatorsDataMock();
        moduleId = 1;
        impl = address(
            new CuratedGate(address(module), moduleId, address(data))
        );
        factory = new CuratedGateFactory(impl);
        root = bytes32(randomBytes(32));
        cid = "someCid";
        curveId = 1;
    }
}

contract CuratedGateFactoryTest_constructor is CuratedGateFactoryTestBase {
    function test_constructor() public {
        CuratedGateFactory f = new CuratedGateFactory(impl);
        assertEq(f.CURATED_GATE_IMPL(), impl);
    }

    function test_constructor_RevertWhen_ZeroImpl() public {
        vm.expectRevert(ICuratedGateFactory.ZeroImplementationAddress.selector);
        new CuratedGateFactory(address(0));
    }
}

contract CuratedGateFactoryTest_create is CuratedGateFactoryTestBase {
    function test_create() public {
        vm.expectEmit(false, false, false, false, address(factory));
        emit ICuratedGateFactory.CuratedGateCreated(address(0));
        address instance = factory.create(curveId, root, cid, admin);

        ICuratedGate gate = ICuratedGate(instance);
        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(module));
        assertEq(gate.MODULE_ID(), moduleId);
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);
        assertEq(address(gate.OPERATORS_DATA()), address(data));

        AccessControlEnumerableUpgradeable access = AccessControlEnumerableUpgradeable(
                instance
            );
        assertEq(access.getRoleMemberCount(access.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin));

        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getAdmin(), admin);
    }
}
