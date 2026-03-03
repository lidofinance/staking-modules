// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "../helpers/Utilities.sol";

import { MerkleGateFactory } from "src/MerkleGateFactory.sol";
import { IMerkleGateFactory } from "src/interfaces/IMerkleGateFactory.sol";
import { IVettedGate } from "src/interfaces/IVettedGate.sol";
import { ICuratedGate } from "src/interfaces/ICuratedGate.sol";
import { VettedGate } from "src/VettedGate.sol";
import { CuratedGate } from "src/CuratedGate.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { MetaRegistryMock } from "../helpers/mocks/MetaRegistryMock.sol";

contract MerkleGateFactoryTest is Test, Utilities {
    bytes32 internal root;
    string internal cid;
    uint256 internal curveId;
    address internal admin;

    function setUp() public {
        root = bytes32(randomBytes(32));
        cid = "someCid";
        curveId = 1;
        admin = nextAddress("admin");
    }

    function test_createVetted() public {
        CSMMock csm = new CSMMock();
        address impl = address(new VettedGate(address(csm)));
        MerkleGateFactory factory = new MerkleGateFactory(impl);
        address expectedInstance = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(address(factory));
        emit IMerkleGateFactory.MerkleGateCreated(expectedInstance, admin, curveId);

        address instance = factory.create(curveId, root, cid, admin);
        IVettedGate gate = IVettedGate(instance);

        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(csm));
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);

        AccessControlEnumerableUpgradeable access = AccessControlEnumerableUpgradeable(instance);
        assertEq(access.getRoleMemberCount(access.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin));

        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getAdmin(), admin);
    }

    function test_createCurated() public {
        CuratedMock module = new CuratedMock();
        MetaRegistryMock metaRegistry = new MetaRegistryMock();
        module.mock_setMetaRegistry(address(metaRegistry));

        address impl = address(new CuratedGate(address(module)));
        MerkleGateFactory factory = new MerkleGateFactory(impl);
        address expectedInstance = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(address(factory));
        emit IMerkleGateFactory.MerkleGateCreated(expectedInstance, admin, curveId);

        address instance = factory.create(curveId, root, cid, admin);
        ICuratedGate gate = ICuratedGate(instance);

        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(module));
        assertEq(address(gate.META_REGISTRY()), address(metaRegistry));
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);

        AccessControlEnumerableUpgradeable access = AccessControlEnumerableUpgradeable(instance);
        assertEq(access.getRoleMemberCount(access.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(access.hasRole(access.DEFAULT_ADMIN_ROLE(), admin));

        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getAdmin(), admin);
    }

    function test_constructor_RevertWhen_ZeroImpl() public {
        vm.expectRevert(IMerkleGateFactory.ZeroImplementationAddress.selector);
        new MerkleGateFactory(address(0));
    }

    function test_create_UsesImmutableImplementation() public {
        CSMMock csm = new CSMMock();
        address impl = address(new VettedGate(address(csm)));
        MerkleGateFactory factory = new MerkleGateFactory(impl);
        assertEq(factory.GATE_IMPL(), impl);

        address secondImpl = address(new VettedGate(address(new CSMMock())));
        address expectedInstance = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        // The factory should always use its immutable implementation.
        vm.expectEmit(address(factory));
        emit IMerkleGateFactory.MerkleGateCreated(expectedInstance, admin, curveId);

        address instance = factory.create(curveId, root, cid, admin);
        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getImplementation(), impl);
        assertNotEq(proxy.proxy__getImplementation(), secondImpl);
    }
}
