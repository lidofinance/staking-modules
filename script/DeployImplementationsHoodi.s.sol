// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { DeployImplementationsBase } from "./DeployImplementationsBase.s.sol";
import { HashConsensus } from "../src/lib/base-oracle/HashConsensus.sol";
import { CSModule } from "../src/CSModule.sol";
import { CSAccounting } from "../src/CSAccounting.sol";
import { CSFeeDistributor } from "../src/CSFeeDistributor.sol";
import { CSFeeOracle } from "../src/CSFeeOracle.sol";
import { CSVerifier } from "../src/CSVerifier.sol";
import { DeploymentHelpers } from "../test/helpers/Fixtures.sol";
import { DeployHoodi } from "./DeployHoodi.s.sol";

contract DeployImplementationsHoodi is
    DeployImplementationsBase,
    DeployHoodi,
    DeploymentHelpers
{
    function deploy(
        string memory deploymentConfigPath,
        string memory _gitRef
    ) external {
        gitRef = _gitRef;
        string memory deploymentConfigContent = vm.readFile(
            deploymentConfigPath
        );
        DeploymentConfig memory deploymentConfig = parseDeploymentConfig(
            deploymentConfigContent
        );

        csm = CSModule(deploymentConfig.csm);
        earlyAdoption = deploymentConfig.earlyAdoption;
        accounting = CSAccounting(deploymentConfig.accounting);
        oracle = CSFeeOracle(deploymentConfig.oracle);
        feeDistributor = CSFeeDistributor(deploymentConfig.feeDistributor);
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        verifier = CSVerifier(deploymentConfig.verifier);
        gateSeal = deploymentConfig.gateSeal;

        _deploy();
    }
}
