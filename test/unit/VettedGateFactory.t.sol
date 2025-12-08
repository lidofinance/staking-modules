// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";
import { VettedGate } from "src/VettedGate.sol";
import { VettedGateFactory } from "src/VettedGateFactory.sol";
import { IVettedGateFactory } from "src/interfaces/IVettedGateFactory.sol";
import { IVettedGate } from "src/interfaces/IVettedGate.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";

contract VettedGateFactoryConstructorTest is Test, Utilities {
    CSMMock csm;
    address vettedGateImpl;

    function setUp() public {
        csm = new CSMMock();
        vettedGateImpl = address(new VettedGate(address(csm)));
    }

    function test_constructor_HappyPath() public {
        VettedGateFactory factory = new VettedGateFactory(vettedGateImpl);
        assertEq(factory.VETTED_GATE_IMPL(), vettedGateImpl);
    }

    function test_constructor_RevertWhen_ZeroImpl() public {
        vm.expectRevert(IVettedGateFactory.ZeroImplementationAddress.selector);
        new VettedGateFactory(address(0));
    }
}

contract VettedGateFactoryTest is Test, Utilities {
    VettedGateFactory factory;
    CSMMock csm;
    bytes32 root;
    string cid;
    uint256 curveId;

    function setUp() public {
        csm = new CSMMock();
        address vettedGateImpl = address(new VettedGate(address(csm)));
        factory = new VettedGateFactory(vettedGateImpl);
        root = bytes32(randomBytes(32));
        cid = "someCid";
        curveId = 1;
    }

    function test_create() public {
        vm.expectEmit(false, false, false, false, address(factory));
        emit IVettedGateFactory.VettedGateCreated(address(0));
        address instance = factory.create(curveId, root, cid, address(this));
        IVettedGate gate = IVettedGate(instance);
        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(csm));
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);

        AccessControlEnumerableUpgradeable gateAccess = AccessControlEnumerableUpgradeable(
                instance
            );
        assertEq(
            gateAccess.getRoleMemberCount(gateAccess.DEFAULT_ADMIN_ROLE()),
            1
        );
        assertTrue(
            gateAccess.hasRole(gateAccess.DEFAULT_ADMIN_ROLE(), address(this))
        );

        OssifiableProxy proxy = OssifiableProxy(payable(instance));
        assertEq(proxy.proxy__getAdmin(), address(this));
    }
}
