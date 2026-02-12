// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "src/CSModule.sol";
import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";

contract ProxyUpgradesCSM0x02 is CSM0x02IntegrationBase {
    function setUp() public {
        _setUpModule();
    }

    function test_CSModuleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CSModule newModule = new CSModule({
            moduleType: "CSM0x02V3",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES())
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newModule));
        assertEq(module.getType(), "CSM0x02V3");
    }

    function test_CSModuleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CSModule newModule = new CSModule({
            moduleType: "CSM0x02V3",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES())
        });
        address contractAdmin = module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(contractAdmin);
        module.grantRole(module.RESUME_ROLE(), address(proxy.proxy__getAdmin()));
        module.grantRole(module.PAUSE_ROLE(), address(proxy.proxy__getAdmin()));
        vm.stopPrank();
        if (!module.isPaused()) {
            vm.prank(proxy.proxy__getAdmin());
            module.pauseFor(100500);
        }
        assertTrue(module.isPaused());
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeToAndCall(address(newModule), abi.encodeWithSelector(newModule.resume.selector, 1));
        assertEq(module.getType(), "CSM0x02V3");
        assertFalse(module.isPaused());
    }
}
