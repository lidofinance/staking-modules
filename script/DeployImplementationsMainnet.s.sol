// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { DeployImplementationsBase } from "./DeployImplementationsBase.s.sol";
import { DeployMainnet } from "./DeployMainnet.s.sol";
import { HashConsensus } from "../src/lib/base-oracle/HashConsensus.sol";
import { CSModule } from "../src/CSModule.sol";
import { Accounting } from "../src/Accounting.sol";
import { FeeDistributor } from "../src/FeeDistributor.sol";
import { FeeOracle } from "../src/FeeOracle.sol";
import { Verifier } from "../src/Verifier.sol";
import { DeploymentHelpers } from "../test/helpers/Fixtures.sol";

contract DeployImplementationsMainnet is
    DeployImplementationsBase,
    DeployMainnet,
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
        accounting = Accounting(deploymentConfig.accounting);
        oracle = FeeOracle(deploymentConfig.oracle);
        feeDistributor = FeeDistributor(deploymentConfig.feeDistributor);
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        verifier = Verifier(deploymentConfig.verifier);
        gateSeal = deploymentConfig.gateSeal;

        _deploy();
    }
}
