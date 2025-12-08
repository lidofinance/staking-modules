// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IStakingRouter } from "../../../src/interfaces/IStakingRouter.sol";

contract StakingRouterMock {
    mapping(uint256 => IStakingRouter.StakingModule) internal _modules;
    uint256[] internal _moduleIds;

    error StakingModuleUnregistered();

    function setModules(address[] memory modules) external {
        _clearModules();
        uint256 length = modules.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 moduleId = i + 1; // module ids start at 1
            IStakingRouter.StakingModule storage moduleData = _modules[
                moduleId
            ];
            // Test IDs grow sequentially from 1, so they never exceed the uint24 field used on mainnet.
            // forge-lint: disable-next-line(unsafe-typecast)
            moduleData.id = uint24(moduleId);
            moduleData.stakingModuleAddress = modules[i];
            _moduleIds.push(moduleId);
        }
    }

    function addModule(uint256 moduleId, address module) external {
        if (moduleId == 0) revert("module id zero");
        IStakingRouter.StakingModule storage moduleData = _modules[moduleId];
        // Module identifiers are constrained to the same uint24 range as production.
        // forge-lint: disable-next-line(unsafe-typecast)
        moduleData.id = uint24(moduleId);
        moduleData.stakingModuleAddress = module;
        bool exists = false;
        uint256 idsLength = _moduleIds.length;
        for (uint256 i = 0; i < idsLength; ++i) {
            if (_moduleIds[i] == moduleId) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            _moduleIds.push(moduleId);
        }
    }

    function getStakingModules()
        external
        view
        returns (IStakingRouter.StakingModule[] memory res)
    {
        uint256 length = _moduleIds.length;
        res = new IStakingRouter.StakingModule[](length);
        for (uint256 i = 0; i < length; ++i) {
            res[i] = _modules[_moduleIds[i]];
        }
    }

    function getStakingModule(
        uint256 moduleId
    ) external view returns (IStakingRouter.StakingModule memory) {
        IStakingRouter.StakingModule memory module = _modules[moduleId];
        if (module.stakingModuleAddress == address(0)) {
            revert StakingModuleUnregistered();
        }
        return module;
    }

    function _clearModules() internal {
        uint256 length = _moduleIds.length;
        for (uint256 i = 0; i < length; ++i) {
            delete _modules[_moduleIds[i]];
        }
        delete _moduleIds;
    }
}
