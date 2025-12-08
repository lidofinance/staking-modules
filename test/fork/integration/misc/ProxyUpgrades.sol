// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { OssifiableProxy } from "../../../../src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "../../../../src/CSModule.sol";
import { Accounting } from "../../../../src/Accounting.sol";
import { FeeDistributor } from "../../../../src/FeeDistributor.sol";
import { FeeOracle } from "../../../../src/FeeOracle.sol";
import { Utilities } from "../../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../../helpers/Fixtures.sol";

contract ProxyUpgrades is Test, Utilities, DeploymentFixtures {
    constructor() {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }

    function test_CSModuleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CSModule newModule = new CSModule({
            moduleType: "CSMv2",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES())
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newModule));
        assertEq(module.getType(), "CSMv2");
    }

    function test_CSModuleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CSModule newModule = new CSModule({
            moduleType: "CSMv2",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES())
        });
        address contractAdmin = module.getRoleMember(
            module.DEFAULT_ADMIN_ROLE(),
            0
        );
        vm.startPrank(contractAdmin);
        module.grantRole(
            module.RESUME_ROLE(),
            address(proxy.proxy__getAdmin())
        );
        module.grantRole(module.PAUSE_ROLE(), address(proxy.proxy__getAdmin()));
        vm.stopPrank();
        if (!module.isPaused()) {
            vm.prank(proxy.proxy__getAdmin());
            module.pauseFor(100500);
        }
        assertTrue(module.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(
            address(newModule),
            abi.encodeWithSelector(newModule.resume.selector, 1)
        );
        assertEq(module.getType(), "CSMv2");
        assertFalse(module.isPaused());
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
        assertEq(
            accounting.MAX_BOND_LOCK_PERIOD(),
            currentMaxBondLockPeriod + 10
        );
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
        address contractAdmin = accounting.getRoleMember(
            accounting.DEFAULT_ADMIN_ROLE(),
            0
        );
        vm.startPrank(contractAdmin);
        accounting.grantRole(
            accounting.PAUSE_ROLE(),
            address(proxy.proxy__getAdmin())
        );
        vm.stopPrank();
        assertFalse(accounting.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(
            address(newAccounting),
            abi.encodeWithSelector(newAccounting.pauseFor.selector, 100500)
        );
        assertEq(
            accounting.MAX_BOND_LOCK_PERIOD(),
            currentMaxBondLockPeriod + 10
        );
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
        address contractAdmin = oracle.getRoleMember(
            oracle.DEFAULT_ADMIN_ROLE(),
            0
        );
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
        OssifiableProxy proxy = OssifiableProxy(
            payable(address(feeDistributor))
        );
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
