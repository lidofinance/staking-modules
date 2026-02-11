// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OssifiableProxy } from "../../../../src/lib/proxy/OssifiableProxy.sol";
import { CuratedModule } from "../../../../src/CuratedModule.sol";
import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract ProxyUpgradesCurated is CuratedIntegrationBase {
    function setUp() public {
        _setUpModule();
    }

    function test_CuratedModuleUpgradeTo() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CuratedModule newModule = new CuratedModule({
            moduleType: "CuratedV3",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES()),
            metaRegistry: address(CuratedModule(address(module)).META_REGISTRY())
        });
        vm.prank(proxy.proxy__getAdmin());
        proxy.proxy__upgradeTo(address(newModule));
        assertEq(module.getType(), "CuratedV3");
    }

    function test_CuratedModuleUpgradeToAndCall() public {
        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));
        CuratedModule newModule = new CuratedModule({
            moduleType: "CuratedV3",
            lidoLocator: address(module.LIDO_LOCATOR()),
            parametersRegistry: address(module.PARAMETERS_REGISTRY()),
            accounting: address(module.ACCOUNTING()),
            exitPenalties: address(module.EXIT_PENALTIES()),
            metaRegistry: address(CuratedModule(address(module)).META_REGISTRY())
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
        assertEq(module.getType(), "CuratedV3");
        assertFalse(module.isPaused());
    }
}
