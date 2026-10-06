// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { WCType, toWC } from "src/utils/WithdrawalCredentials.sol";

contract WithdrawalCredentialsTest is Test {
    function test_toWC() public pure {
        address withdrawalAddress = address(0x1234);
        bytes32 addressPart = bytes32(uint256(uint160(withdrawalAddress)));

        assertEq(toWC(withdrawalAddress, WCType.BLS), addressPart);
        assertEq(toWC(withdrawalAddress, WCType.Eth1), bytes32(bytes1(0x01)) | addressPart);
        assertEq(toWC(withdrawalAddress, WCType.Compounding), bytes32(bytes1(0x02)) | addressPart);
    }
}
