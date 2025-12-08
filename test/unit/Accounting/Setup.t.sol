// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { BaseConstructorTest, BaseInitTest } from "./_Base.t.sol";
import { Accounting } from "src/Accounting.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IBondLock } from "src/interfaces/IBondLock.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Combined setup tests: constructor and initialization

contract ConstructorTest is BaseConstructorTest {
    function test_constructor_happyPath() public {
        accounting = new Accounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days
        );
        assertEq(address(accounting.MODULE()), address(stakingModule));
        assertEq(
            address(accounting.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
        assertEq(
            address(accounting.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        accounting = new Accounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days
        );

        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accounting.initialize(
            curve,
            admin,
            8 weeks,
            testChargePenaltyRecipient
        );
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IAccounting.ZeroModuleAddress.selector);
        accounting = new Accounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            365 days
        );
    }

    function test_constructor_RevertWhen_ZeroFeeDistributorAddress() public {
        vm.expectRevert(IAccounting.ZeroFeeDistributorAddress.selector);
        accounting = new Accounting(
            address(locator),
            address(stakingModule),
            address(0),
            4 weeks,
            365 days
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MinMoreThanMax()
        public
    {
        vm.expectRevert(IBondLock.InvalidBondLockPeriod.selector);
        accounting = new Accounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            2 weeks
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MaxTooBig()
        public
    {
        vm.expectRevert(IBondLock.InvalidBondLockPeriod.selector);
        accounting = new Accounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            uint256(type(uint64).max) + 1
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MinIsZero()
        public
    {
        vm.expectRevert(IBondLock.InvalidBondLockPeriod.selector);
        accounting = new Accounting(
            address(locator),
            address(0),
            address(feeDistributor),
            0,
            154 days
        );
    }
}

contract InitTest is BaseInitTest {
    function test_initialize_happyPath() public assertInvariants {
        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectEmit(address(accounting));
        emit IBondCurve.BondCurveAdded(0, curve);
        vm.expectEmit(address(accounting));
        emit IBondLock.BondLockPeriodChanged(8 weeks);
        vm.expectEmit(address(accounting));
        emit IAccounting.ChargePenaltyRecipientSet(testChargePenaltyRecipient);
        accounting.initialize(
            curve,
            admin,
            8 weeks,
            testChargePenaltyRecipient
        );

        assertEq(accounting.getInitializedVersion(), 3);
    }

    function test_initialize_RevertWhen_zeroAdmin() public {
        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectRevert(IAccounting.ZeroAdminAddress.selector);
        accounting.initialize(
            curve,
            address(0),
            8 weeks,
            testChargePenaltyRecipient
        );
    }

    function test_initialize_RevertWhen_zeroChargePenaltyRecipient() public {
        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectRevert(IAccounting.ZeroChargePenaltyRecipientAddress.selector);
        accounting.initialize(curve, admin, 8 weeks, address(0));
    }

    function test_finalizeUpgradeV3() public {
        _enableInitializers(address(accounting));

        accounting.finalizeUpgradeV3();

        assertEq(accounting.getInitializedVersion(), 3);
    }
}
