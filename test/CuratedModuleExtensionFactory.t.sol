// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { Utilities } from "./helpers/Utilities.sol";

import { CuratedModuleExtension } from "../src/CuratedModuleExtension.sol";
import { ICuratedModuleExtension } from "../src/interfaces/ICuratedModuleExtension.sol";
import { CuratedModuleExtensionFactory } from "../src/CuratedModuleExtensionFactory.sol";
import { ICuratedModuleExtensionFactory } from "../src/interfaces/ICuratedModuleExtensionFactory.sol";

import { CSMMock } from "./helpers/mocks/CSMMock.sol";
import { OperatorsDataMock } from "./helpers/mocks/OperatorsDataMock.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { OssifiableProxy } from "../src/lib/proxy/OssifiableProxy.sol";

contract CuratedModuleExtensionFactoryTestBase is Test, Utilities {
    CuratedModuleExtensionFactory factory;
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
        impl = address(
            new CuratedModuleExtension(address(module), address(data))
        );
        factory = new CuratedModuleExtensionFactory(impl);
        root = bytes32(randomBytes(32));
        cid = "someCid";
        curveId = 1;
    }
}

contract CuratedModuleExtensionFactoryTest_constructor is
    CuratedModuleExtensionFactoryTestBase
{
    function test_constructor() public {
        CuratedModuleExtensionFactory f = new CuratedModuleExtensionFactory(
            impl
        );
        assertEq(f.CURATED_MODULE_EXTENSION_IMPL(), impl);
    }

    function test_constructor_RevertWhen_ZeroImpl() public {
        vm.expectRevert(
            ICuratedModuleExtensionFactory.ZeroImplementationAddress.selector
        );
        new CuratedModuleExtensionFactory(address(0));
    }
}

contract CuratedModuleExtensionFactoryTest_create is
    CuratedModuleExtensionFactoryTestBase
{
    function test_create() public {
        vm.expectEmit(false, false, false, false, address(factory));
        emit ICuratedModuleExtensionFactory.CuratedModuleExtensionCreated(
            address(0)
        );
        address instance = factory.create(curveId, root, cid, admin);

        ICuratedModuleExtension ext = ICuratedModuleExtension(instance);
        assertEq(ext.curveId(), curveId);
        assertEq(address(ext.MODULE()), address(module));
        assertEq(ext.treeRoot(), root);
        assertEq(ext.treeCid(), cid);
        assertEq(address(ext.OPERATORS_DATA()), address(data));

        AccessControlEnumerableUpgradeable access = AccessControlEnumerableUpgradeable(
                instance
            );
        assertEq(access.getRoleMemberCount(access.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin));

        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getAdmin(), admin);
    }
}
