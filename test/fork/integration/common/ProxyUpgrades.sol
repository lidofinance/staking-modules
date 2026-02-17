// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OssifiableProxy } from "../../../../src/lib/proxy/OssifiableProxy.sol";
import { Accounting } from "../../../../src/Accounting.sol";
import { FeeDistributor } from "../../../../src/FeeDistributor.sol";
import { FeeOracle } from "../../../../src/FeeOracle.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract ProxyUpgradesBase is ModuleTypeBase {
    function setUp() public {
        _setUpModule();
    }

    function test_AccountingUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(accounting)));
        uint256 currentMaxBondLockPeriod = accounting.MAX_BOND_LOCK_PERIOD();
        Accounting newAccounting = new Accounting({
            lidoLocator: address(accounting.LIDO_LOCATOR()),
            module: address(module),
            feeDistributor: address(feeDistributor),
            minBondLockPeriod: accounting.MIN_BOND_LOCK_PERIOD(),
            maxBondLockPeriod: currentMaxBondLockPeriod + 10
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newAccounting));
        assertEq(accounting.MAX_BOND_LOCK_PERIOD(), currentMaxBondLockPeriod + 10);
    }

    function test_AccountingUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(accounting)));
        uint256 currentMaxBondLockPeriod = accounting.MAX_BOND_LOCK_PERIOD();
        Accounting newAccounting = new Accounting({
            lidoLocator: address(accounting.LIDO_LOCATOR()),
            module: address(module),
            feeDistributor: address(feeDistributor),
            minBondLockPeriod: accounting.MIN_BOND_LOCK_PERIOD(),
            maxBondLockPeriod: currentMaxBondLockPeriod + 10
        });
        address contractAdmin = accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(contractAdmin);
        accounting.grantRole(accounting.PAUSE_ROLE(), address(proxy.proxy__getAdmin()));
        vm.stopPrank();
        assertFalse(accounting.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(
            address(newAccounting),
            abi.encodeWithSelector(newAccounting.pauseFor.selector, 100500)
        );
        assertEq(accounting.MAX_BOND_LOCK_PERIOD(), currentMaxBondLockPeriod + 10);
        assertTrue(accounting.isPaused());
    }

    function test_FeeOracleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(oracle)));
        FeeOracle newFeeOracle = new FeeOracle({
            feeDistributor: address(feeDistributor),
            strikes: address(strikes),
            secondsPerSlot: oracle.SECONDS_PER_SLOT(),
            genesisTime: block.timestamp
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newFeeOracle));
        assertEq(oracle.GENESIS_TIME(), block.timestamp);
    }

    function test_FeeOracleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(oracle)));
        FeeOracle newFeeOracle = new FeeOracle({
            feeDistributor: address(feeDistributor),
            strikes: address(strikes),
            secondsPerSlot: oracle.SECONDS_PER_SLOT(),
            genesisTime: block.timestamp
        });
        address contractAdmin = oracle.getRoleMember(oracle.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(contractAdmin);
        oracle.grantRole(oracle.PAUSE_ROLE(), address(proxy.proxy__getAdmin()));
        vm.stopPrank();
        assertFalse(oracle.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(
            address(newFeeOracle),
            abi.encodeWithSelector(newFeeOracle.pauseFor.selector, 100500)
        );
        assertEq(oracle.GENESIS_TIME(), block.timestamp);
        assertTrue(oracle.isPaused());
    }

    function test_FeeDistributorUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(feeDistributor)));
        FeeDistributor newFeeDistributor = new FeeDistributor({
            stETH: locator.lido(),
            accounting: address(1337),
            oracle: address(oracle)
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newFeeDistributor));
        assertEq(feeDistributor.ACCOUNTING(), address(1337));
    }

    // upgradeToAndCall test seems useless for FeeDistributor
}

contract ProxyUpgradesCommonCSM is ProxyUpgradesBase, CSMIntegrationBase {}

contract ProxyUpgradesCommonCSM0x02 is ProxyUpgradesBase, CSM0x02IntegrationBase {}

contract ProxyUpgradesCommonCurated is ProxyUpgradesBase, CuratedIntegrationBase {}
