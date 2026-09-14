// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

contract Library {
    function scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) external pure returns (uint256) {
        return WithdrawnValidatorLib._scalePenaltyByMultiplier(penalty, multiplier);
    }

    function getPenaltyMultiplier(uint256 balance) external pure returns (uint256 penaltyMultiplier) {
        return WithdrawnValidatorLib._getPenaltyMultiplier(balance);
    }

    function clamp(uint256 v, uint256 min, uint256 max) external pure returns (uint256) {
        return WithdrawnValidatorLib._clamp(v, min, max);
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
        uint256 m;
        uint256 balance;

        balance = 32 ether;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 32);

        balance = 32 ether + 1 wei;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 32);

        balance = 33 ether - 1 wei;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 32);

        balance = 33 ether;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 33);

        balance = 33 ether + 1 wei;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 33);

        balance = 2048 ether - 1;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 2047);

        balance = 2048 ether;
        m = lib.getPenaltyMultiplier(balance);
        assertEq(m, 2048);
    }

    function test_clamp_Bounds() public {
        uint256 min = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        uint256 max = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE;

        assertEq(lib.clamp(0, min, max), min);
        assertEq(lib.clamp(min - 1 wei, min, max), min);
        assertEq(lib.clamp(min, min, max), min);
        assertEq(lib.clamp(min + 1 wei, min, max), min + 1 wei);
        assertEq(lib.clamp(max - 1 wei, min, max), max - 1 wei);
        assertEq(lib.clamp(max, min, max), max);
        assertEq(lib.clamp(max + 1 wei, min, max), max);
    }
}
