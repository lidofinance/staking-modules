// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCSMImplementationsBase } from "./DeployCSMImplementationsBase.s.sol";
import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { CSModule } from "../../src/CSModule.sol";
import { Accounting } from "../../src/Accounting.sol";
import { FeeDistributor } from "../../src/FeeDistributor.sol";
import { FeeOracle } from "../../src/FeeOracle.sol";
import { PermissionlessGate } from "../../src/PermissionlessGate.sol";
import { ParametersRegistry } from "../../src/ParametersRegistry.sol";
import { VettedGate } from "../../src/VettedGate.sol";
import { ExitPenalties } from "../../src/ExitPenalties.sol";
import { ValidatorStrikes } from "../../src/ValidatorStrikes.sol";
import { Ejector } from "../../src/Ejector.sol";
import { Verifier } from "../../src/Verifier.sol";
import { DeploymentHelpers } from "../../test/helpers/Fixtures.sol";
import { DeployHoodi } from "./DeployHoodi.s.sol";

contract DeployCSMImplementationsHoodi is DeployCSMImplementationsBase, DeployHoodi, DeploymentHelpers {
    function deploy(string memory deploymentConfigPath, string memory _gitRef) external {
        gitRef = _gitRef;
        string memory deploymentConfigContent = vm.readFile(deploymentConfigPath);
        DeploymentConfig memory deploymentConfig = parseDeploymentConfig(deploymentConfigContent);

        csm = CSModule(deploymentConfig.csm);
        earlyAdoption = deploymentConfig.earlyAdoption;
        accounting = Accounting(deploymentConfig.accounting);
        oracle = FeeOracle(deploymentConfig.oracle);
        feeDistributor = FeeDistributor(deploymentConfig.feeDistributor);
        permissionlessGate = PermissionlessGate(deploymentConfig.permissionlessGate);
        parametersRegistry = ParametersRegistry(deploymentConfig.parametersRegistry);
        vettedGate = VettedGate(deploymentConfig.vettedGate);
        exitPenalties = ExitPenalties(deploymentConfig.exitPenalties);
        ejector = Ejector(payable(deploymentConfig.ejector));
        strikes = ValidatorStrikes(deploymentConfig.strikes);
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        verifier = Verifier(deploymentConfig.verifier);
        gateSeal = deploymentConfig.gateSeal;

        _deploy();
    }
}
