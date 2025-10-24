// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { OssifiableProxy } from "../../../../src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "../../../../src/CSModule.sol";
import { CSAccounting } from "../../../../src/CSAccounting.sol";
import { CSFeeDistributor } from "../../../../src/CSFeeDistributor.sol";
import { CSFeeOracle } from "../../../../src/CSFeeOracle.sol";
import { Utilities } from "../../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../../helpers/Fixtures.sol";

contract ProxyUpgrades is Test, Utilities, DeploymentFixtures {
    constructor() {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }

    function test_CSModuleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(csm)));
        CSModule newModule = new CSModule({
            moduleType: "CSMv2",
            lidoLocator: address(csm.LIDO_LOCATOR()),
            parametersRegistry: address(csm.PARAMETERS_REGISTRY()),
            _accounting: address(csm.ACCOUNTING()),
            exitPenalties: address(csm.EXIT_PENALTIES())
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newModule));
        assertEq(csm.getType(), "CSMv2");
    }

    function test_CSModuleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(csm)));
        CSModule newModule = new CSModule({
            moduleType: "CSMv2",
            lidoLocator: address(csm.LIDO_LOCATOR()),
            parametersRegistry: address(csm.PARAMETERS_REGISTRY()),
            _accounting: address(csm.ACCOUNTING()),
            exitPenalties: address(csm.EXIT_PENALTIES())
        });
        address contractAdmin = csm.getRoleMember(csm.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(contractAdmin);
        csm.grantRole(csm.RESUME_ROLE(), address(proxy.proxy__getAdmin()));
        csm.grantRole(csm.PAUSE_ROLE(), address(proxy.proxy__getAdmin()));
        vm.stopPrank();
        if (!csm.isPaused()) {
            vm.prank(proxy.proxy__getAdmin());
            csm.pauseFor(100500);
        }
        assertTrue(csm.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(
            address(newModule),
            abi.encodeWithSelector(newModule.resume.selector, 1)
        );
        assertEq(csm.getType(), "CSMv2");
        assertFalse(csm.isPaused());
    }

    function test_CSAccountingUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(accounting)));
        uint256 currentMaxBondLockPeriod = accounting.MAX_BOND_LOCK_PERIOD();
        CSAccounting newAccounting = new CSAccounting({
            lidoLocator: address(accounting.LIDO_LOCATOR()),
            module: address(csm),
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

    function test_CSAccountingUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(accounting)));
        uint256 currentMaxBondLockPeriod = accounting.MAX_BOND_LOCK_PERIOD();
        CSAccounting newAccounting = new CSAccounting({
            lidoLocator: address(accounting.LIDO_LOCATOR()),
            module: address(csm),
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

    function test_CSFeeOracleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(oracle)));
        CSFeeOracle newFeeOracle = new CSFeeOracle({
            feeDistributor: address(feeDistributor),
            strikes: address(strikes),
            secondsPerSlot: oracle.SECONDS_PER_SLOT(),
            genesisTime: block.timestamp
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newFeeOracle));
        assertEq(oracle.GENESIS_TIME(), block.timestamp);
    }

    function test_CSFeeOracleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(oracle)));
        CSFeeOracle newFeeOracle = new CSFeeOracle({
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

    function test_CSFeeDistributorUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(
            payable(address(feeDistributor))
        );
        CSFeeDistributor newFeeDistributor = new CSFeeDistributor({
            stETH: locator.lido(),
            accounting: address(1337),
            oracle: address(oracle)
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newFeeDistributor));
        assertEq(feeDistributor.ACCOUNTING(), address(1337));
    }

    // upgradeToAndCall test seems useless for CSFeeDistributor
}
