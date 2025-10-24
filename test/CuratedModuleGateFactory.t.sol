// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { Utilities } from "./helpers/Utilities.sol";

import { CuratedModuleGate } from "../src/CuratedModuleGate.sol";
import { ICuratedModuleGate } from "../src/interfaces/ICuratedModuleGate.sol";
import { CuratedModuleGateFactory } from "../src/CuratedModuleGateFactory.sol";
import { ICuratedModuleGateFactory } from "../src/interfaces/ICuratedModuleGateFactory.sol";

import { CSMMock } from "./helpers/mocks/CSMMock.sol";
import { OperatorsDataMock } from "./helpers/mocks/OperatorsDataMock.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { OssifiableProxy } from "../src/lib/proxy/OssifiableProxy.sol";

contract CuratedModuleGateFactoryTestBase is Test, Utilities {
    CuratedModuleGateFactory factory;
    CSMMock module;
    OperatorsDataMock data;
    address impl;
    bytes32 root;
    string cid;
    uint256 curveId;

    address admin;

    function setUp() public virtual {
        admin = nextAddress("admin");
        module = new CSMMock();
        data = new OperatorsDataMock();
        impl = address(new CuratedModuleGate(address(module), address(data)));
        factory = new CuratedModuleGateFactory(impl);
        root = bytes32(randomBytes(32));
        cid = "someCid";
        curveId = 1;
    }
}

contract CuratedModuleGateFactoryTest_constructor is
    CuratedModuleGateFactoryTestBase
{
    function test_constructor() public {
        CuratedModuleGateFactory f = new CuratedModuleGateFactory(impl);
        assertEq(f.CURATED_MODULE_GATE_IMPL(), impl);
    }

    function test_constructor_RevertWhen_ZeroImpl() public {
        vm.expectRevert(
            ICuratedModuleGateFactory.ZeroImplementationAddress.selector
        );
        new CuratedModuleGateFactory(address(0));
    }
}

contract CuratedModuleGateFactoryTest_create is
    CuratedModuleGateFactoryTestBase
{
    function test_create() public {
        vm.expectEmit(false, false, false, false, address(factory));
        emit ICuratedModuleGateFactory.CuratedModuleGateCreated(address(0));
        address instance = factory.create(curveId, root, cid, admin);

        ICuratedModuleGate gate = ICuratedModuleGate(instance);
        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(module));
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
