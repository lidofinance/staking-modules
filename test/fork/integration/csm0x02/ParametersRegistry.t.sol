// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ParametersRegistryTestBase } from "../common/ParametersRegistry.t.sol";
import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";

contract ParametersRegistryTestCSM0x02 is ParametersRegistryTestBase, CSM0x02IntegrationBase {
    function test_changeKeyRemovalCharge() public assertInvariants {
        _assertChangeKeyRemovalCharge();
    }

    function test_setQueueConfig() public assertInvariants {
        _assertSetQueueConfig();
    }
}
