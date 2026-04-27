// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeploymentFixtures, IForkIntegrationHelpers, CSMIntegrationHelpers, CuratedIntegrationHelpers } from "../../../helpers/Fixtures.sol";
import { Utilities } from "../../../helpers/Utilities.sol";
import { InvariantAsserts } from "../../../helpers/InvariantAsserts.sol";

abstract contract ModuleTypeBase is DeploymentFixtures, Utilities, InvariantAsserts {
    IForkIntegrationHelpers internal integrationHelpers;

    function _setUpModule() internal virtual;

    function _assertModuleEnqueuedCount() internal virtual;

    function _forkAndInitialize() internal {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }
}

abstract contract CSMIntegrationBase is ModuleTypeBase {
    function _setUpModule() internal override {
        _forkAndInitialize();
        if (moduleType != ModuleType.Community) vm.skip(true, "Integration suite requires Community module type");
        integrationHelpers = new CSMIntegrationHelpers(module, accounting, stakingRouter, permissionlessGate);
    }

    function _assertModuleEnqueuedCount() internal override {
        assertModuleEnqueuedCount(module);
    }
}

abstract contract CSM0x02IntegrationBase is ModuleTypeBase {
    function _setUpModule() internal override {
        _forkAndInitialize();
        if (moduleType != ModuleType.Community0x02) {
            vm.skip(true, "Integration suite requires Community0x02 module type");
        }
        integrationHelpers = new CSMIntegrationHelpers(module, accounting, stakingRouter, permissionlessGate);
    }

    function _assertModuleEnqueuedCount() internal override {
        assertModuleEnqueuedCount(module);
    }
}

abstract contract CuratedIntegrationBase is ModuleTypeBase {
    function _setUpModule() internal override {
        _forkAndInitialize();
        if (moduleType != ModuleType.Curated) vm.skip(true, "Integration suite requires Curated module type");
        integrationHelpers = new CuratedIntegrationHelpers(module, accounting, stakingRouter, curatedGates);
    }

    function _assertModuleEnqueuedCount() internal override {}
}
