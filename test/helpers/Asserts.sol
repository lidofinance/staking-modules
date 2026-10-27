// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

import { Accounting } from "src/Accounting.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IPausableWithRoles } from "src/interfaces/IPausableWithRoles.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";

import { ProxySlotUtils } from "./ProxySlotUtils.sol";

abstract contract Asserts is Test {
    function _checkAdminRole(address target, address admin, address secondAdmin) internal view {
        IAccessControlEnumerable accessControl = IAccessControlEnumerable(target);
        bytes32 role = bytes32(0); // DEFAULT_ADMIN_ROLE
        uint256 expectedMembers = block.chainid == 1 ? 1 : 2;

        assertTrue(accessControl.hasRole(role, admin), "missing admin default admin role");
        if (secondAdmin != address(0)) {
            assertTrue(accessControl.hasRole(role, secondAdmin), "missing second admin default admin role");
        }
        assertEq(accessControl.getRoleMemberCount(role), expectedMembers, "unexpected default admin role member count");
    }

    function _checkPauseRole(address target, address resealManager, address cb) internal view {
        IPausableWithRoles pausable = IPausableWithRoles(target);
        IAccessControlEnumerable accessControl = IAccessControlEnumerable(target);
        bytes32 role = pausable.PAUSE_ROLE();
        uint256 expectedRoleMembers = 2;

        assertTrue(accessControl.hasRole(role, resealManager), "reseal manager pause role");
        assertTrue(accessControl.hasRole(role, cb), "circuit breaker pause role");

        assertEq(accessControl.getRoleMemberCount(role), expectedRoleMembers, "pause role member count");
    }

    function _assertBondCurve(
        Accounting accounting,
        uint256 curveId,
        uint256[2][] storage expectedCurve
    ) internal view {
        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo(curveId);
        assertEq(curve.intervals.length, expectedCurve.length);
        uint256 minBond;
        for (uint256 i; i < curve.intervals.length; ++i) {
            uint256 minKeysCount = expectedCurve[i][0];
            uint256 trend = expectedCurve[i][1];
            if (i == 0) {
                minBond = trend;
            } else {
                uint256 prevMinKeysCount = expectedCurve[i - 1][0];
                uint256 prevTrend = expectedCurve[i - 1][1];
                minBond += trend + (minKeysCount - prevMinKeysCount - 1) * prevTrend;
            }
            assertEq(curve.intervals[i].minKeysCount, minKeysCount);
            assertEq(curve.intervals[i].minBond, minBond);
            assertEq(curve.intervals[i].trend, trend);
            assertEq(accounting.getBondAmountByKeysCount(minKeysCount, curveId), minBond);
        }
    }

    function _assertProxy(
        address proxyAddress,
        address implementation,
        address admin,
        string memory name
    ) internal view {
        OssifiableProxy proxy = OssifiableProxy(payable(proxyAddress));
        assertEq(proxy.proxy__getImplementation(), implementation, string.concat(name, " proxy getter impl"));
        assertEq(
            ProxySlotUtils.getImplementation(proxyAddress),
            implementation,
            string.concat(name, " proxy slot impl")
        );
        assertEq(proxy.proxy__getAdmin(), admin, string.concat(name, " proxy getter admin"));
        assertEq(ProxySlotUtils.getAdmin(proxyAddress), admin, string.concat(name, " proxy slot admin"));
        assertFalse(proxy.proxy__getIsOssified(), string.concat(name, " proxy ossified"));
    }
}
