// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import { DeploymentFixtures } from "test/helpers/Fixtures.sol";

import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "../../src/CSModule.sol";
import { CSAccounting } from "../../src/CSAccounting.sol";
import { CSFeeOracle } from "../../src/CSFeeOracle.sol";
import { CSFeeDistributor } from "../../src/CSFeeDistributor.sol";
import { CSEjector } from "../../src/CSEjector.sol";
import { CSParametersRegistry } from "../../src/CSParametersRegistry.sol";

import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ICSBondCurve } from "../../src/interfaces/ICSBondCurve.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";
import { ICSParametersRegistry } from "../../src/interfaces/ICSParametersRegistry.sol";

import { CommonScriptUtils } from "../utils/Common.sol";

import { ForkHelpersCommon } from "./Common.sol";
import { DeployParams } from "../DeployBase.s.sol";

contract SimulateVote is Script, DeploymentFixtures, ForkHelpersCommon {
    function addModule() external {
        _setUp();

        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        IBurner burner = IBurner(locator.burner());

        address agent = stakingRouter.getRoleMember(
            stakingRouter.STAKING_MODULE_MANAGE_ROLE(),
            0
        );
        vm.label(agent, "agent");

        address csmAdmin = _prepareAdmin(address(csm));
        address burnerAdmin = _prepareAdmin(address(burner));

        vm.startBroadcast(csmAdmin);
        csm.grantRole(csm.DEFAULT_ADMIN_ROLE(), agent);
        hashConsensus.grantRole(hashConsensus.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(burnerAdmin);
        burner.grantRole(burner.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(agent);

        // 1. Add CommunityStaking module
        stakingRouter.addStakingModule({
            _name: "community-staking-v1",
            _stakingModuleAddress: address(csm),
            _stakeShareLimit: 2000, // 20%
            _priorityExitShareThreshold: 2500, // 25%
            _stakingModuleFee: 800, // 8%
            _treasuryFee: 200, // 2%
            _maxDepositsPerBlock: 30,
            _minDepositBlockDistance: 25
        });
        // 2. burner role
        burner.grantRole(
            burner.REQUEST_BURN_SHARES_ROLE(),
            address(accounting)
        );
        // 3. Grant resume to agent
        csm.grantRole(csm.RESUME_ROLE(), agent);
        // 4. Resume CSM
        csm.resume();
        // 5. Revoke resume
        csm.revokeRole(csm.RESUME_ROLE(), agent);
        // 6. Update initial epoch
        hashConsensus.updateInitialEpoch(47480);
    }

    function upgrade() external {
        Env memory env = envVars();
        string memory deploymentConfigContent = vm.readFile(env.DEPLOY_CONFIG);
        DeploymentConfig memory deploymentConfig = parseDeploymentConfig(
            deploymentConfigContent
        );
        DeployParams memory deployParams = parseDeployParams(env.DEPLOY_CONFIG);
        //
        // TODO: uncomment and change when v2 -> v3 upgrade flow is ready
        //
        //     ICSBondCurve.BondCurveIntervalInput[][]
        //         memory bondCurves = new ICSBondCurve.BondCurveIntervalInput[][](
        //             2 + deployParams.extraBondCurves.length
        //         );
        //     bondCurves[0] = CommonScriptUtils.arraysToBondCurveIntervalsInputs(
        //         deployParams.defaultBondCurve
        //     );
        //     bondCurves[1] = CommonScriptUtils.arraysToBondCurveIntervalsInputs(
        //         deployParams.legacyEaBondCurve
        //     );
        //     if (deployParams.extraBondCurves.length > 0) {
        //         for (uint256 i = 0; i < deployParams.extraBondCurves.length; i++) {
        //             bondCurves[i + 2] = CommonScriptUtils
        //                 .arraysToBondCurveIntervalsInputs(
        //                     deployParams.extraBondCurves[i]
        //                 );
        //         }
        //     }

        //     ICSBondCurve.BondCurveIntervalInput[]
        //         memory identifiedCommunityStakersGateBondCurve = CommonScriptUtils
        //             .arraysToBondCurveIntervalsInputs(
        //                 deployParams.identifiedCommunityStakersGateBondCurve
        //             );

        //     address admin = _prepareAdmin(deploymentConfig.csm);

        //     OssifiableProxy csmProxy = OssifiableProxy(
        //         payable(deploymentConfig.csm)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(csmProxy)));
        //     {
        //         csmProxy.proxy__upgradeTo(deploymentConfig.csmImpl);
        //         CSModule(deploymentConfig.csm).finalizeUpgradeV2();
        //     }
        //     vm.stopBroadcast();
        //     OssifiableProxy accountingProxy = OssifiableProxy(
        //         payable(deploymentConfig.accounting)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(accountingProxy)));
        //     {
        //         accountingProxy.proxy__upgradeTo(deploymentConfig.accountingImpl);
        //         CSAccounting(deploymentConfig.accounting).finalizeUpgradeV3(
        //             deployParams.bondReserveMinPeriod
        //         );
        //     }
        //     vm.stopBroadcast();

        //     OssifiableProxy oracleProxy = OssifiableProxy(
        //         payable(deploymentConfig.oracle)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(oracleProxy)));
        //     {
        //         oracleProxy.proxy__upgradeTo(deploymentConfig.oracleImpl);
        //         CSFeeOracle(deploymentConfig.oracle).finalizeUpgradeV2({
        //             consensusVersion: 3
        //         });
        //     }
        //     vm.stopBroadcast();

        //     OssifiableProxy feeDistributorProxy = OssifiableProxy(
        //         payable(deploymentConfig.feeDistributor)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(feeDistributorProxy)));
        //     {
        //         feeDistributorProxy.proxy__upgradeTo(
        //             deploymentConfig.feeDistributorImpl
        //         );
        //         CSFeeDistributor(deploymentConfig.feeDistributor).finalizeUpgradeV2(
        //             admin
        //         );
        //     }
        //     vm.stopBroadcast();

        //     csm = CSModule(deploymentConfig.csm);
        //     accounting = CSAccounting(deploymentConfig.accounting);
        //     oracle = CSFeeOracle(deploymentConfig.oracle);

        //     vm.startBroadcast(admin);

        //     accounting.revokeRole(accounting.SET_BOND_CURVE_ROLE(), address(csm));
        //     csm.grantRole(
        //         csm.CREATE_NODE_OPERATOR_ROLE(),
        //         deploymentConfig.permissionlessGate
        //     );
        //     csm.grantRole(
        //         csm.CREATE_NODE_OPERATOR_ROLE(),
        //         deploymentConfig.vettedGate
        //     );
        //     accounting.grantRole(
        //         accounting.SET_BOND_CURVE_ROLE(),
        //         deploymentConfig.vettedGate
        //     );

        //     accounting.grantRole(accounting.MANAGE_BOND_CURVES_ROLE(), admin);

        //     accounting.addBondCurve(identifiedCommunityStakersGateBondCurve);

        //     accounting.revokeRole(accounting.MANAGE_BOND_CURVES_ROLE(), admin);

        //     csm.revokeRole(csm.VERIFIER_ROLE(), address(deploymentConfig.verifier));
        //     csm.grantRole(
        //         csm.VERIFIER_ROLE(),
        //         address(deploymentConfig.verifierV2)
        //     );
        //     TODO: Grant VERIFIER_ROLE on CSModule to EasyTrack executor.

        //     csm.revokeRole(csm.PAUSE_ROLE(), address(deploymentConfig.gateSeal));
        //     accounting.revokeRole(
        //         accounting.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSeal)
        //     );
        //     oracle.revokeRole(
        //         oracle.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSeal)
        //     );

        //     csm.grantRole(csm.PAUSE_ROLE(), address(deploymentConfig.gateSealV2));
        //     accounting.grantRole(
        //         accounting.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSealV2)
        //     );
        //     oracle.grantRole(
        //         oracle.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSealV2)
        //     );

        //     csm.grantRole(csm.PAUSE_ROLE(), deployParams.resealManager);
        //     csm.grantRole(csm.RESUME_ROLE(), deployParams.resealManager);
        //     accounting.grantRole(
        //         accounting.PAUSE_ROLE(),
        //         deployParams.resealManager
        //     );
        //     accounting.grantRole(
        //         accounting.RESUME_ROLE(),
        //         deployParams.resealManager
        //     );
        //     oracle.grantRole(oracle.PAUSE_ROLE(), deployParams.resealManager);
        //     oracle.grantRole(oracle.RESUME_ROLE(), deployParams.resealManager);

        //     accounting.revokeRole(keccak256("RESET_BOND_CURVE_ROLE"), address(csm));
        //     address csmCommittee = accounting.getRoleMember(
        //         keccak256("RESET_BOND_CURVE_ROLE"),
        //         0
        //     );
        //     accounting.revokeRole(
        //         keccak256("RESET_BOND_CURVE_ROLE"),
        //         address(csmCommittee)
        //     );

        //     vm.stopBroadcast();
    }
}
