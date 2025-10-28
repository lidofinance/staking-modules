// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IStakingRouter } from "../../../src/interfaces/IStakingRouter.sol";

contract StakingRouterMock {
    address[] internal _modules;

    function setModules(address[] memory modules) external {
        _modules = modules;
    }

    function getStakingModules()
        external
        view
        returns (IStakingRouter.StakingModule[] memory res)
    {
        address[] memory modules = _modules;
        res = new IStakingRouter.StakingModule[](modules.length);
        for (uint256 i = 0; i < modules.length; ++i) {
            res[i].stakingModuleAddress = modules[i];
        }
    }
}
