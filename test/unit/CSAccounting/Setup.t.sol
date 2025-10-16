// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "./_Base.t.sol";

// Combined setup tests: constructor and initialization

contract ConstructorTest is BaseConstructorTest {
    function test_constructor_happyPath() public {
        accounting = new CSAccounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days,
            true
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
        accounting = new CSAccounting(
            address(locator),
            address(stakingModule),
            address(feeDistributor),
            4 weeks,
            365 days,
            true
        );

        ICSBondCurve.BondCurveIntervalInput[]
            memory curve = new ICSBondCurve.BondCurveIntervalInput[](1);
        curve[0] = ICSBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accounting.initialize(
            curve,
            admin,
            8 weeks,
            8 weeks,
            testChargePenaltyRecipient
        );
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(ICSAccounting.ZeroModuleAddress.selector);
        accounting = new CSAccounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            365 days,
            true
        );
    }

    function test_constructor_RevertWhen_ZeroFeeDistributorAddress() public {
        vm.expectRevert(ICSAccounting.ZeroFeeDistributorAddress.selector);
        accounting = new CSAccounting(
            address(locator),
            address(stakingModule),
            address(0),
            4 weeks,
            365 days,
            true
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MinMoreThanMax()
        public
    {
        vm.expectRevert(ICSBondLock.InvalidBondLockPeriod.selector);
        accounting = new CSAccounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            2 weeks,
            true
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MaxTooBig()
        public
    {
        vm.expectRevert(ICSBondLock.InvalidBondLockPeriod.selector);
        accounting = new CSAccounting(
            address(locator),
            address(0),
            address(feeDistributor),
            4 weeks,
            uint256(type(uint64).max) + 1,
            true
        );
    }

    function test_constructor_RevertWhen_InvalidBondLockPeriod_MinIsZero()
        public
    {
        vm.expectRevert(ICSBondLock.InvalidBondLockPeriod.selector);
        accounting = new CSAccounting(
            address(locator),
            address(0),
            address(feeDistributor),
            0,
            154 days,
            true
        );
    }
}

contract InitTest is BaseInitTest {
    function test_initialize_happyPath() public assertInvariants {
        ICSBondCurve.BondCurveIntervalInput[]
            memory curve = new ICSBondCurve.BondCurveIntervalInput[](1);
        curve[0] = ICSBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectEmit(address(accounting));
        emit ICSBondCurve.BondCurveAdded(0, curve);
        vm.expectEmit(address(accounting));
        emit ICSBondLock.BondLockPeriodChanged(8 weeks);
        vm.expectEmit(address(accounting));
        emit ICSAccounting.ChargePenaltyRecipientSet(
            testChargePenaltyRecipient
        );
        accounting.initialize(
            curve,
            admin,
            8 weeks,
            4 weeks,
            testChargePenaltyRecipient
        );

        assertEq(accounting.getInitializedVersion(), 3);
    }

    function test_initialize_RevertWhen_zeroAdmin() public {
        ICSBondCurve.BondCurveIntervalInput[]
            memory curve = new ICSBondCurve.BondCurveIntervalInput[](1);
        curve[0] = ICSBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectRevert(ICSAccounting.ZeroAdminAddress.selector);
        accounting.initialize(
            curve,
            address(0),
            8 weeks,
            4 weeks,
            testChargePenaltyRecipient
        );
    }

    function test_initialize_RevertWhen_zeroChargePenaltyRecipient() public {
        ICSBondCurve.BondCurveIntervalInput[]
            memory curve = new ICSBondCurve.BondCurveIntervalInput[](1);
        curve[0] = ICSBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        _enableInitializers(address(accounting));

        vm.expectRevert(
            ICSAccounting.ZeroChargePenaltyRecipientAddress.selector
        );
        accounting.initialize(curve, admin, 8 weeks, 4 weeks, address(0));
    }

    function test_finalizeUpgradeV3() public {
        _enableInitializers(address(accounting));

        accounting.finalizeUpgradeV3(4 weeks);

        assertEq(accounting.getInitializedVersion(), 3);
    }
}
