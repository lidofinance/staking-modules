// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

contract Library {
    function scalePenaltyByMultiplier(
        uint256 penalty,
        uint256 multiplier
    ) external pure returns (uint256) {
        return
            WithdrawnValidatorLib._scalePenaltyByMultiplier(
                penalty,
                multiplier
            );
    }

    function getPenaltyMultiplier(
        WithdrawnValidatorInfo memory validatorInfo
    ) external pure returns (uint256 penaltyMultiplier) {
        return WithdrawnValidatorLib._getPenaltyMultiplier(validatorInfo);
    }
}

contract TestWithdrawnValidatorLib is Test {
    Library internal lib;

    function setUp() public {
        lib = new Library();
    }

    function test_scalePenaltyByMultiplier() public {
        uint256 s;

        s = lib.scalePenaltyByMultiplier(33, 33);
        assertEq(s, 34);

        s = lib.scalePenaltyByMultiplier(3300000, 33);
        assertEq(s, 3403125);

        s = lib.scalePenaltyByMultiplier(0.1 ether, 33);
        assertEq(s, 0.103125 ether);

        s = lib.scalePenaltyByMultiplier(0.1 ether, 1041);
        assertEq(s, 3.253125 ether);

        s = lib.scalePenaltyByMultiplier(0.1 ether, 2048);
        assertEq(s, 6.4 ether);

        s = lib.scalePenaltyByMultiplier(32 ether, 1);
        assertEq(s, 1 ether);

        s = lib.scalePenaltyByMultiplier(32 ether, 2048);
        assertEq(s, 2048 ether);
    }

    function test_getPenaltyMultiplier_Step() public {
        WithdrawnValidatorInfo memory info;
        uint256 m;

        info.exitBalance = 0;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 1 ether;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 32 ether - 1 wei;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 32 ether;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 32 ether + 1 wei;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 33 ether - 1 wei;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 32);

        info.exitBalance = 33 ether;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 33);

        info.exitBalance = 33 ether + 1 wei;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 33);

        info.exitBalance = 2048 ether - 1;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 2047);

        info.exitBalance = 2048 ether;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 2048);

        info.exitBalance = 2048 ether + 1 wei;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 2048);

        info.exitBalance = 2049 ether;
        m = lib.getPenaltyMultiplier(info);
        assertEq(m, 2048);
    }
}
