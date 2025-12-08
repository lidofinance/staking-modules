// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { ValidatorCountsReport } from "src/lib/ValidatorCountsReport.sol";

contract ReportCaller {
    function safeCountOperators(
        bytes calldata ids,
        bytes calldata counts
    ) public pure returns (uint256) {
        return ValidatorCountsReport.safeCountOperators(ids, counts);
    }

    function next(
        bytes calldata ids,
        bytes calldata counts,
        uint256 offset
    ) public pure returns (uint256 nodeOperatorId, uint256 _count) {
        return ValidatorCountsReport.next(ids, counts, offset);
    }
}

contract ValidatorCountsReportTest is Test {
    ReportCaller caller;

    function setUp() public {
        caller = new ReportCaller();
    }

    function test_safeCountOperators() public view {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(bytes8(0x0000000000000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        caller.safeCountOperators(ids, counts);
    }

    function test_safeCountOperators_invalidIdsLength() public {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(bytes8(0x0000000000000001), bytes4(0x00000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.expectRevert(ValidatorCountsReport.InvalidReportData.selector);
        caller.safeCountOperators(ids, counts);
    }

    function test_safeCountOperators_invalidCountsLength() public {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(bytes8(0x0000000000000001)),
            bytes.concat(
                bytes16(0x00000000000000000000000000000001),
                bytes4(0x00000001)
            )
        );

        vm.expectRevert(ValidatorCountsReport.InvalidReportData.selector);
        caller.safeCountOperators(ids, counts);
    }

    function test_safeCountOperators_differentItemsCount() public {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(
                bytes8(0x0000000000000001),
                bytes8(0x0000000000000002)
            ),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.expectRevert(ValidatorCountsReport.InvalidReportData.selector);
        caller.safeCountOperators(ids, counts);
    }

    function test_count() public view {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(bytes8(0x0000000000000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        assertEq(caller.safeCountOperators(ids, counts), 1);
    }

    function test_next() public view {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(bytes8(0x0000000000000001)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        (uint256 nodeOperatorId, uint256 count) = caller.next(ids, counts, 0);
        assertEq(nodeOperatorId, 1, "nodeOperatorId != 1");
        assertEq(count, 1, "count != 1");
    }

    function test_nextWithOffset() public view {
        (bytes memory ids, bytes memory counts) = (
            bytes.concat(
                bytes8(0x0000000000000001),
                bytes8(0x0000000000000002)
            ),
            bytes.concat(
                bytes16(0x00000000000000000000000000000001),
                bytes16(0x00000000000000000000000000000002)
            )
        );

        (uint256 nodeOperatorId, uint256 count) = caller.next(ids, counts, 1);
        assertEq(nodeOperatorId, 2, "nodeOperatorId != 2");
        assertEq(count, 2, "count != 2");
    }
}
