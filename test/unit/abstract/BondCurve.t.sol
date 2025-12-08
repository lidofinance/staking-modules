// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BondCurve } from "src/abstract/BondCurve.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";

contract BondCurveTestable is BondCurve {
    function initialize(
        IBondCurve.BondCurveIntervalInput[] calldata bondCurve
    ) public initializer {
        __BondCurve_init(bondCurve);
    }

    function addBondCurve(
        IBondCurve.BondCurveIntervalInput[] calldata _bondCurve
    ) external returns (uint256) {
        return _addBondCurve(_bondCurve);
    }

    function updateBondCurve(
        uint256 curveId,
        IBondCurve.BondCurveIntervalInput[] calldata _bondCurve
    ) external {
        _updateBondCurve(curveId, _bondCurve);
    }

    function setBondCurve(uint256 nodeOperatorId, uint256 curveId) external {
        _setBondCurve(nodeOperatorId, curveId);
    }
}

contract BondCurveInitTest is Test {
    BondCurveTestable public bondCurve;

    function setUp() public {
        bondCurve = new BondCurveTestable();
    }

    function test_initialize_revertWhen_InvalidInitializationCurveId() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);

        bondCurve.addBondCurve(_bondCurve);

        vm.expectRevert(IBondCurve.InvalidInitializationCurveId.selector);
        bondCurve.initialize(_bondCurve);
    }
}

contract BondCurveTest is Test {
    BondCurveTestable public bondCurve;

    function setUp() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(3, 1 ether);
        bondCurve = new BondCurveTestable();
        vm.startSnapshotGas("bondCurve.initialize");
        bondCurve.initialize(_bondCurve);
        vm.stopSnapshotGas();
    }

    function test_getCurveInfo() public view {
        IBondCurve.BondCurveData memory curve = bondCurve.getCurveInfo(0);

        assertEq(curve.intervals.length, 2);
        assertEq(curve.intervals[0].minKeysCount, 1);
        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
        assertEq(curve.intervals[1].minKeysCount, 3);
        assertEq(curve.intervals[1].minBond, 5 ether);
        assertEq(curve.intervals[1].trend, 1 ether);
    }

    function test_getCurveInfo_RevertWhen_InvalidBondCurveId() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        bondCurve.getCurveInfo(1337);
    }

    function test_addBondCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);

        uint256 curvesCount = bondCurve.getCurvesCount();

        vm.expectEmit(address(bondCurve));
        emit IBondCurve.BondCurveAdded(curvesCount, _bondCurve);

        uint256 addedId = bondCurve.addBondCurve(_bondCurve);

        IBondCurve.BondCurveData memory added = bondCurve.getCurveInfo(addedId);

        assertEq(addedId, 1);
        assertEq(added.intervals.length, 1);
        assertEq(added.intervals[0].minKeysCount, 1);
        assertEq(added.intervals[0].minBond, 16 ether);
        assertEq(added.intervals[0].trend, 16 ether);
    }

    function test_addBondCurve_SeveralIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](4);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(10, 1 ether);
        _bondCurve[2] = IBondCurve.BondCurveIntervalInput(33, 0.5 ether);
        _bondCurve[3] = IBondCurve.BondCurveIntervalInput(100, 10 ether);

        uint256 addedId = bondCurve.addBondCurve(_bondCurve);

        IBondCurve.BondCurveData memory added = bondCurve.getCurveInfo(addedId);

        assertEq(addedId, 1);
        assertEq(added.intervals.length, 4);
        assertEq(added.intervals[0].minKeysCount, 1);
        assertEq(added.intervals[0].minBond, 16 ether);
        assertEq(added.intervals[0].trend, 16 ether);

        assertEq(added.intervals[1].minKeysCount, 10);
        assertEq(added.intervals[1].minBond, 145 ether);
        assertEq(added.intervals[1].trend, 1 ether);

        assertEq(added.intervals[2].minKeysCount, 33);
        assertEq(added.intervals[2].minBond, 167.5 ether);
        assertEq(added.intervals[2].trend, 0.5 ether);

        assertEq(added.intervals[3].minKeysCount, 100);
        assertEq(added.intervals[3].minBond, 210.5 ether);
        assertEq(added.intervals[3].trend, 10 ether);
    }

    function test_addBondCurve_RevertWhen_LessThanMinBondCurveLength() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveLength.selector);
        bondCurve.addBondCurve(new IBondCurve.BondCurveIntervalInput[](0));
    }

    function test_addBondCurve_RevertWhen_MoreThanMaxBondCurveLength() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveLength.selector);
        bondCurve.addBondCurve(new IBondCurve.BondCurveIntervalInput[](101));
    }

    function test_addBondCurve_RevertWhen_ZeroTrend() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 0 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.addBondCurve(_bondCurve);
    }

    function test_addBondCurve_RevertWhen_ZeroTrendSecondInterval() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 0 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.addBondCurve(_bondCurve);
    }

    function test_addBondCurve_RevertWhen_FirstIntervalStartsFromNonOne()
        public
    {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(2, 1 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.addBondCurve(_bondCurve);
    }

    function test_addBondCurve_RevertWhen_UnsortedIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(1, 1 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.addBondCurve(_bondCurve);
    }

    function test_updateBondCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);

        uint256 toUpdateId = 0;

        vm.expectEmit(address(bondCurve));
        emit IBondCurve.BondCurveUpdated(toUpdateId, _bondCurve);

        bondCurve.updateBondCurve(toUpdateId, _bondCurve);

        IBondCurve.BondCurveData memory updated = bondCurve.getCurveInfo(
            toUpdateId
        );

        assertEq(updated.intervals.length, 1);
        assertEq(updated.intervals[0].minKeysCount, 1);
        assertEq(updated.intervals[0].minBond, 16 ether);
        assertEq(updated.intervals[0].trend, 16 ether);
    }

    function test_updateBondCurve_SeveralIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](4);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(10, 1 ether);
        _bondCurve[2] = IBondCurve.BondCurveIntervalInput(33, 0.5 ether);
        _bondCurve[3] = IBondCurve.BondCurveIntervalInput(100, 10 ether);

        uint256 toUpdateId = 0;

        bondCurve.updateBondCurve(toUpdateId, _bondCurve);

        IBondCurve.BondCurveData memory updated = bondCurve.getCurveInfo(
            toUpdateId
        );

        assertEq(updated.intervals.length, 4);
        assertEq(updated.intervals[0].minKeysCount, 1);
        assertEq(updated.intervals[0].minBond, 16 ether);
        assertEq(updated.intervals[0].trend, 16 ether);

        assertEq(updated.intervals[1].minKeysCount, 10);
        assertEq(updated.intervals[1].minBond, 145 ether);
        assertEq(updated.intervals[1].trend, 1 ether);

        assertEq(updated.intervals[2].minKeysCount, 33);
        assertEq(updated.intervals[2].minBond, 167.5 ether);
        assertEq(updated.intervals[2].trend, 0.5 ether);

        assertEq(updated.intervals[3].minKeysCount, 100);
        assertEq(updated.intervals[3].minBond, 210.5 ether);
        assertEq(updated.intervals[3].trend, 10 ether);
    }

    function test_updateBondCurve_RevertWhen_LessThanMinBondCurveLength()
        public
    {
        vm.expectRevert(IBondCurve.InvalidBondCurveLength.selector);
        bondCurve.updateBondCurve(
            0,
            new IBondCurve.BondCurveIntervalInput[](0)
        );
    }

    function test_updateBondCurve_RevertWhen_MoreThanMaxBondCurveLength()
        public
    {
        vm.expectRevert(IBondCurve.InvalidBondCurveLength.selector);
        bondCurve.updateBondCurve(
            0,
            new IBondCurve.BondCurveIntervalInput[](101)
        );
    }

    function test_updateBondCurve_RevertWhen_ZeroTrend() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 0 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.updateBondCurve(0, _bondCurve);
    }

    function test_updateBondCurve_RevertWhen_ZeroTrendSecondInterval() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 0 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.updateBondCurve(0, _bondCurve);
    }

    function test_updateBondCurve_RevertWhen_FirstIntervalStartsFromNonOne()
        public
    {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(2, 1 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.updateBondCurve(0, _bondCurve);
    }

    function test_updateBondCurve_RevertWhen_UnsortedIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(1, 1 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveValues.selector);
        bondCurve.updateBondCurve(0, _bondCurve);
    }

    function test_updateBondCurve_RevertWhen_InvalidBondCurveId() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);

        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        bondCurve.updateBondCurve(1, _bondCurve);
    }

    function test_setBondCurve() public {
        uint256 noId = 0;
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);
        uint256 addedId = bondCurve.addBondCurve(_bondCurve);

        vm.expectEmit(address(bondCurve));
        emit IBondCurve.BondCurveSet(noId, addedId);
        bondCurve.setBondCurve(noId, addedId);

        assertEq(bondCurve.getBondCurveId(noId), addedId);
    }

    function test_setBondCurve_RevertWhen_NoExistingCurveId() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        bondCurve.setBondCurve(0, 100500);
    }

    function test_getCurvesCount() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 16 ether);

        bondCurve.addBondCurve(_bondCurve);

        // default one + 1 extra curve
        assertEq(bondCurve.getCurvesCount(), 2);
    }

    function test_getCurvesCount_noExtraCurves() public view {
        // only default one
        assertEq(bondCurve.getCurvesCount(), 1);
    }

    function test_getKeysCountByBondAmount_default() public view {
        assertEq(bondCurve.getKeysCountByBondAmount(0, 0), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(1.9 ether, 0), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(2 ether, 0), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(2.1 ether, 0), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(4 ether, 0), 2);
        assertEq(bondCurve.getKeysCountByBondAmount(5 ether, 0), 3);
        assertEq(bondCurve.getKeysCountByBondAmount(5.1 ether, 0), 3);
        assertEq(bondCurve.getKeysCountByBondAmount(6 ether, 0), 4);
    }

    function test_getKeysCountByBondAmount_noOverflowWithMaxUint() public view {
        IBondCurve.BondCurveData memory curve = bondCurve.getBondCurve(0);
        uint256 len = curve.intervals.length;
        IBondCurve.BondCurveInterval memory lastInterval = curve.intervals[
            len - 1
        ];
        uint256 amount = type(uint256).max;

        assertEq(
            bondCurve.getKeysCountByBondAmount(amount, 0),
            lastInterval.minKeysCount +
                (amount - lastInterval.minBond) /
                lastInterval.trend
        );
    }

    function test_getKeysCountByBondAmount_noOverflowWithMinUint() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 wei);
        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        uint256 amount = type(uint256).max;

        assertEq(
            bondCurve.getKeysCountByBondAmount(amount, curveId),
            type(uint256).max
        );
    }

    function test_getBondAmountByKeysCount_default() public view {
        assertEq(bondCurve.getBondAmountByKeysCount(0, 0), 0);
        assertEq(bondCurve.getBondAmountByKeysCount(1, 0), 2 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(2, 0), 4 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(3, 0), 5 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(4, 0), 6 ether);
    }

    function test_getKeysCountByCurveValue_individual() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 ether);
        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getKeysCountByBondAmount(0 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(1 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(2 ether, curveId), 2);

        _bondCurve[0].trend = 1.8 ether;
        curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getKeysCountByBondAmount(0 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(1.8 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(5.39 ether, curveId), 2);
    }

    function test_getKeysCountByBondAmount_singlePointCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);
        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getKeysCountByBondAmount(0 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(1 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(2 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(3 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(4 ether, curveId), 2);
        assertEq(bondCurve.getKeysCountByBondAmount(5 ether, curveId), 2);
    }

    function test_getKeysCountByBondAmount_twoPointsCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](2);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 2 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 1.5 ether);

        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getKeysCountByBondAmount(0 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(1 ether, curveId), 0);
        assertEq(bondCurve.getKeysCountByBondAmount(2 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(3 ether, curveId), 1);
        assertEq(bondCurve.getKeysCountByBondAmount(3.5 ether, curveId), 2);
        assertEq(bondCurve.getKeysCountByBondAmount(4 ether, curveId), 2);
        assertEq(bondCurve.getKeysCountByBondAmount(5 ether, curveId), 3);
        assertEq(bondCurve.getKeysCountByBondAmount(6 ether, curveId), 3);
    }

    function test_getKeysCountByBondAmount_tenPointsCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 ether);
        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        for (uint256 i = 0; i < 10; i++) {
            assertEq(
                bondCurve.getKeysCountByBondAmount(i * 1 ether, curveId),
                i
            );
            assertEq(
                bondCurve.getKeysCountByBondAmount(
                    i * 1 ether + 0.5 ether,
                    curveId
                ),
                i
            );
        }
    }

    function test_getBondAmountByKeysCount_individual() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1 ether);
        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getBondAmountByKeysCount(0, curveId), 0);
        assertEq(bondCurve.getBondAmountByKeysCount(1, curveId), 1 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(2, curveId), 2 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(3, curveId), 3 ether);

        _bondCurve[0].trend = 1.8 ether;
        curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getBondAmountByKeysCount(0, curveId), 0);
        assertEq(bondCurve.getBondAmountByKeysCount(1, curveId), 1.8 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(2, curveId), 3.6 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(3, curveId), 5.4 ether);
    }

    function test_getBondAmountByKeysCount_bigCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](3);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1.5 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 1 ether);
        _bondCurve[2] = IBondCurve.BondCurveIntervalInput(4, 0.5 ether);

        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        assertEq(bondCurve.getBondAmountByKeysCount(0, curveId), 0);
        assertEq(bondCurve.getBondAmountByKeysCount(1, curveId), 1.5 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(2, curveId), 2.5 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(3, curveId), 3.5 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(4, curveId), 4 ether);
        assertEq(bondCurve.getBondAmountByKeysCount(16, curveId), 10 ether);
    }

    function test_viceVersa_OneInterval() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](1);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 0.33 ether);

        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        for (uint256 keysIn = 0; keysIn < 100; ++keysIn) {
            uint256 bondOut = bondCurve.getBondAmountByKeysCount(
                keysIn,
                curveId
            );
            assertEq(
                bondCurve.getKeysCountByBondAmount(bondOut, curveId),
                keysIn
            );
        }

        for (
            uint256 bondIn = 0 ether;
            bondIn < 33 ether;
            bondIn += 0.33 ether
        ) {
            uint256 keysOut = bondCurve.getKeysCountByBondAmount(
                bondIn,
                curveId
            );
            assertGe(
                bondIn,
                bondCurve.getBondAmountByKeysCount(keysOut, curveId)
            );
        }
    }

    function test_viceVersa_ThreeIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](3);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1.5 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 1 ether);
        _bondCurve[2] = IBondCurve.BondCurveIntervalInput(4, 0.5 ether);

        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        for (uint256 keysIn = 0; keysIn < 100; ++keysIn) {
            uint256 bondOut = bondCurve.getBondAmountByKeysCount(
                keysIn,
                curveId
            );
            assertEq(
                bondCurve.getKeysCountByBondAmount(bondOut, curveId),
                keysIn
            );
        }

        for (
            uint256 bondIn = 0 ether;
            bondIn < 33 ether;
            bondIn += 0.33 ether
        ) {
            uint256 keysOut = bondCurve.getKeysCountByBondAmount(
                bondIn,
                curveId
            );
            assertGe(
                bondIn,
                bondCurve.getBondAmountByKeysCount(keysOut, curveId)
            );
        }
    }

    function test_viceVersa_SixIntervals() public {
        IBondCurve.BondCurveIntervalInput[]
            memory _bondCurve = new IBondCurve.BondCurveIntervalInput[](6);
        _bondCurve[0] = IBondCurve.BondCurveIntervalInput(1, 1.5 ether);
        _bondCurve[1] = IBondCurve.BondCurveIntervalInput(2, 1 ether);
        _bondCurve[2] = IBondCurve.BondCurveIntervalInput(4, 0.5 ether);
        _bondCurve[3] = IBondCurve.BondCurveIntervalInput(5, 0.5 ether + 1 wei);
        _bondCurve[4] = IBondCurve.BondCurveIntervalInput(
            13,
            1.11 ether - 1 wei
        );
        _bondCurve[5] = IBondCurve.BondCurveIntervalInput(16, 0.01 ether);

        uint256 curveId = bondCurve.addBondCurve(_bondCurve);

        for (uint256 keysIn = 0; keysIn < 100; ++keysIn) {
            uint256 bondOut = bondCurve.getBondAmountByKeysCount(
                keysIn,
                curveId
            );
            assertEq(
                bondCurve.getKeysCountByBondAmount(bondOut, curveId),
                keysIn
            );
        }

        for (
            uint256 bondIn = 0 ether;
            bondIn < 33 ether;
            bondIn += 0.33 ether
        ) {
            uint256 keysOut = bondCurve.getKeysCountByBondAmount(
                bondIn,
                curveId
            );
            assertGe(
                bondIn,
                bondCurve.getBondAmountByKeysCount(keysOut, curveId)
            );
        }
    }
}

contract BondCurveFuzz is Test {
    BondCurveTestable public bondCurve;

    uint256 public constant MAX_BOND_CURVE_INTERVALS_COUNT = 100;
    uint256 public constant MAX_FROM_KEYS_COUNT_VALUE = 10000;
    uint256 public constant MAX_TREND_VALUE = 1000 ether;

    function testFuzz_keysAndBondValues(
        uint256[] memory minKeysCount,
        uint256[] memory trend,
        uint256 keysToCheck,
        uint256 bondToCheck
    ) public {
        uint256[2][] memory _bondCurve;
        (_bondCurve, keysToCheck, bondToCheck) = prepareInputs(
            minKeysCount,
            trend,
            keysToCheck,
            bondToCheck
        );
        bondCurve = new BondCurveTestable();
        IBondCurve.BondCurveIntervalInput[]
            memory bondCurveInput = new IBondCurve.BondCurveIntervalInput[](
                _bondCurve.length
            );
        for (uint256 i = 0; i < _bondCurve.length; ++i) {
            bondCurveInput[i] = IBondCurve.BondCurveIntervalInput(
                _bondCurve[i][0],
                _bondCurve[i][1]
            );
        }
        bondCurve.initialize(bondCurveInput);
        IBondCurve.BondCurveData memory defaultBondCurve = bondCurve
            .getCurveInfo(0);

        // Compare contract output with different algorithm
        uint256 keysCountSecondOpinion = getKeysCountByBondAmountSecondOpinion(
            defaultBondCurve.intervals,
            bondToCheck
        );
        uint256 keysCount = bondCurve.getKeysCountByBondAmount(bondToCheck, 0);
        assertEq(
            keysCount,
            keysCountSecondOpinion,
            "keysCount != keysCountSecondOpinion"
        );
        // Can't check this fully, because of the rounding (`bondToCheck` can be "between" two keys amounts).
        // So it is enough to check that one less or equal than another
        uint256 bondMinKeysCount = bondCurve.getBondAmountByKeysCount(
            keysCount,
            0
        );
        assertGe(
            bondToCheck,
            bondMinKeysCount,
            "bondminKeysCount > bondToCheck"
        );

        uint256 bondAmountSecondOpinion = getBondAmountByKeysCountSecondOpinion(
            defaultBondCurve.intervals,
            keysToCheck
        );
        uint256 bondAmount = bondCurve.getBondAmountByKeysCount(keysToCheck, 0);
        assertEq(
            bondAmount,
            bondAmountSecondOpinion,
            "bondAmount != bondOutSecondOpinion"
        );
        // Check that values are the same in both directions
        uint256 keysMinBondAmount = bondCurve.getKeysCountByBondAmount(
            bondAmount,
            0
        );
        assertEq(
            keysMinBondAmount,
            keysToCheck,
            "keysMinBondAmount != keysToCheck"
        );
    }

    /// NOTE: Ugly, ineffective version of binary search algorithm from the contract.
    //        Needed only as a second opinion to compare outputs.
    function getBondAmountByKeysCountSecondOpinion(
        IBondCurve.BondCurveInterval[] memory intervals,
        uint256 keysToCheck
    ) public pure returns (uint256) {
        uint256 bondAmount = 0;
        uint256 minBondAcc = intervals[0].trend;
        for (uint256 i = 0; i < intervals.length; ++i) {
            if (i > 0) {
                // Current trend + difference between current and previous minKeysCount multiplied by previous trend
                minBondAcc +=
                    intervals[i].trend +
                    (intervals[i].minKeysCount -
                        intervals[i - 1].minKeysCount -
                        1) *
                    intervals[i - 1].trend;
            }
            if (keysToCheck >= intervals[i].minKeysCount) {
                bondAmount =
                    minBondAcc +
                    (keysToCheck - intervals[i].minKeysCount) *
                    intervals[i].trend;
            } else {
                break;
            }
        }
        return bondAmount;
    }

    /// NOTE: Ugly, ineffective version of binary search algorithm from the contract.
    //        Needed only as a second opinion to compare outputs.
    function getKeysCountByBondAmountSecondOpinion(
        IBondCurve.BondCurveInterval[] memory intervals,
        uint256 bondToCheck
    ) public pure returns (uint256) {
        if (bondToCheck < intervals[0].minBond) {
            return 0;
        }

        uint256 neededIndex = 0;
        uint256 minBondAcc = intervals[0].trend;
        for (uint256 i = 0; i < intervals.length; i++) {
            if (i > 0) {
                // Current trend + difference between current and previous minKeysCount multiplied by previous trend
                minBondAcc +=
                    intervals[i].trend +
                    (intervals[i].minKeysCount -
                        intervals[i - 1].minKeysCount -
                        1) *
                    intervals[i - 1].trend;
            }
            if (bondToCheck == minBondAcc) {
                return intervals[i].minKeysCount;
            }
            if (i < intervals.length - 1) {
                uint256 nextMinBond = minBondAcc +
                    intervals[i + 1].trend +
                    (intervals[i + 1].minKeysCount -
                        intervals[i].minKeysCount -
                        1) *
                    intervals[i].trend;
                if (bondToCheck < nextMinBond) {
                    uint256 maxBondInInterval = nextMinBond -
                        intervals[i + 1].trend;
                    if (bondToCheck > maxBondInInterval) {
                        bondToCheck = maxBondInInterval;
                    }
                    neededIndex = i;
                    break;
                }
            }
            neededIndex = i;
        }

        return
            intervals[neededIndex].minKeysCount +
            (bondToCheck - minBondAcc) /
            intervals[neededIndex].trend;
    }

    function prepareInputs(
        uint256[] memory minKeysCount,
        uint256[] memory trend,
        uint256 keysToCheck,
        uint256 bondToCheck
    ) public pure returns (uint256[2][] memory, uint256, uint256) {
        vm.assume(minKeysCount.length > 0);
        vm.assume(trend.length > 0);

        // Assume: intervals.length > 0
        uint256 intervalsCount = Math.max(
            1,
            Math.min(minKeysCount.length, trend.length) %
                MAX_BOND_CURVE_INTERVALS_COUNT
        );
        for (uint256 i = 0; i < intervalsCount; ++i) {
            // Assume: minKeysCount[i] > 0
            minKeysCount[i] = Math.max(
                1,
                minKeysCount[i] % MAX_FROM_KEYS_COUNT_VALUE
            );
            // Assume: trend[i] > 0
            trend[i] = Math.max(1 wei, trend[i] % MAX_TREND_VALUE);
        }
        assembly ("memory-safe") {
            // Shrink `minKeysCount` and `trend` arrays to `intervalsCount`
            mstore(minKeysCount, intervalsCount)
            mstore(trend, intervalsCount)
        }

        // Assume: minKeysCount[i] < minKeysCount[i + 1]
        uint256 n = minKeysCount.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n - 1; j++) {
                if (minKeysCount[j] > minKeysCount[j + 1]) {
                    (minKeysCount[j], minKeysCount[j + 1]) = (
                        minKeysCount[j + 1],
                        minKeysCount[j]
                    );
                }
                if (minKeysCount[j] == minKeysCount[j + 1]) {
                    // Make it different because we need to have unique values
                    minKeysCount[j + 1] = minKeysCount[j] + 1;
                }
            }
        }
        // Assume: first interval starts from "1" keys count
        minKeysCount[0] = 1;

        assertEq(minKeysCount.length, trend.length);

        // Dev: zip `minKeysCount` and `trend` arrays to `uint256[2][] intervals`
        uint256[2][] memory _bondCurve = new uint256[2][](minKeysCount.length);
        for (uint256 i = 0; i < intervalsCount; ++i) {
            _bondCurve[i] = [minKeysCount[i], trend[i]];
        }
        keysToCheck = bound(keysToCheck, 1, MAX_FROM_KEYS_COUNT_VALUE);
        bondToCheck = bound(bondToCheck, trend[0], type(uint256).max);
        return (_bondCurve, keysToCheck, bondToCheck);
    }
}
