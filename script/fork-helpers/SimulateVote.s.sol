// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script } from "forge-std/Script.sol";

import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ITriggerableWithdrawalsGateway } from "../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";

import { ForkHelpersCommon } from "./Common.sol";
import { DeployParams } from "../DeployBase.s.sol";

contract SimulateVote is Script, ForkHelpersCommon {
    bytes32 internal constant REPORT_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("REPORT_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 internal constant SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE");

    error WrongModuleType();

    function addModule() external {
        _setUp();
        if (moduleType != ModuleType.Community) {
            revert WrongModuleType();
        }

        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        IBurner burner = IBurner(locator.burner());
        ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(
            locator.triggerableWithdrawalsGateway()
        );

        address agent = stakingRouter.getRoleMember(
            stakingRouter.STAKING_MODULE_MANAGE_ROLE(),
            0
        );
        vm.label(agent, "agent");

        address moduleAdmin = _prepareAdmin(address(module));
        address burnerAdmin = _prepareAdmin(address(burner));
        address twgAdmin = _prepareAdmin(address(twg));

        vm.startBroadcast(burnerAdmin);
        burner.grantRole(burner.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(twgAdmin);
        twg.grantRole(twg.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(agent);

        // 1. Add CommunityStaking module
        stakingRouter.addStakingModule({
            _name: "community-staking-v1",
            _stakingModuleAddress: address(module),
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
        // 3. twg role
        twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), address(ejector));
        // 4. Grant resume to agent
        module.grantRole(module.RESUME_ROLE(), agent);
        // 5. Resume CSM
        module.resume();
        // 6. Revoke resume
        module.revokeRole(module.RESUME_ROLE(), agent);
        // 7. Update initial epoch
        hashConsensus.updateInitialEpoch(47480);

        vm.stopBroadcast();
    }

    function addCuratedModule() external {
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) {
            revert WrongModuleType();
        }

        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        IBurner burner = IBurner(locator.burner());
        ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(
            locator.triggerableWithdrawalsGateway()
        );

        address agent = stakingRouter.getRoleMember(
            stakingRouter.STAKING_MODULE_MANAGE_ROLE(),
            0
        );
        vm.label(agent, "agent");

        address curatedAdmin = _prepareAdmin(address(curatedModule));
        address burnerAdmin = _prepareAdmin(address(burner));
        address twgAdmin = _prepareAdmin(address(twg));

        vm.startBroadcast(burnerAdmin);
        burner.grantRole(burner.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(twgAdmin);
        twg.grantRole(twg.DEFAULT_ADMIN_ROLE(), agent);
        vm.stopBroadcast();

        vm.startBroadcast(agent);

        stakingRouter.addStakingModule({
            _name: "curated-onchain-v1",
            _stakingModuleAddress: address(curatedModule),
            _stakeShareLimit: 2000, // 20%
            _priorityExitShareThreshold: 2500, // 25%
            _stakingModuleFee: 800, // 8%
            _treasuryFee: 200, // 2%
            _maxDepositsPerBlock: 30,
            _minDepositBlockDistance: 25
        });

        burner.grantRole(
            burner.REQUEST_BURN_SHARES_ROLE(),
            address(accounting)
        );

        twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), address(ejector));

        curatedModule.grantRole(curatedModule.RESUME_ROLE(), agent);
        curatedModule.resume();
        curatedModule.revokeRole(curatedModule.RESUME_ROLE(), agent);
        hashConsensus.updateInitialEpoch(47480);

        vm.stopBroadcast();
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
        //     IBondCurve.BondCurveIntervalInput[][]
        //         memory bondCurves = new IBondCurve.BondCurveIntervalInput[][](
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

        //     IBondCurve.BondCurveIntervalInput[]
        //         memory identifiedCommunityStakersGateBondCurve = CommonScriptUtils
        //             .arraysToBondCurveIntervalsInputs(
        //                 deployParams.identifiedCommunityStakersGateBondCurve
        //             );

        //     address admin = _prepareAdmin(deploymentConfig.module);

        //     OssifiableProxy moduleProxy = OssifiableProxy(
        //         payable(deploymentConfig.module)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(moduleProxy)));
        //     {
        //         moduleProxy.proxy__upgradeTo(deploymentConfig.moduleImpl);
        //         CSModule(deploymentConfig.module).finalizeUpgradeV2();
        //     }
        //     vm.stopBroadcast();
        //     OssifiableProxy accountingProxy = OssifiableProxy(
        //         payable(deploymentConfig.accounting)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(accountingProxy)));
        //     {
        //         accountingProxy.proxy__upgradeTo(deploymentConfig.accountingImpl);
        //         Accounting(deploymentConfig.accounting).finalizeUpgradeV3();
        //     }
        //     vm.stopBroadcast();

        //     OssifiableProxy oracleProxy = OssifiableProxy(
        //         payable(deploymentConfig.oracle)
        //     );
        //     vm.startBroadcast(_prepareProxyAdmin(address(oracleProxy)));
        //     {
        //         oracleProxy.proxy__upgradeTo(deploymentConfig.oracleImpl);
        //         FeeOracle(deploymentConfig.oracle).finalizeUpgradeV2({
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
        //         FeeDistributor(deploymentConfig.feeDistributor).finalizeUpgradeV2(
        //             admin
        //         );
        //     }
        //     vm.stopBroadcast();

        //     module = CSModule(deploymentConfig.module);
        //     accounting = Accounting(deploymentConfig.accounting);
        //     oracle = FeeOracle(deploymentConfig.oracle);

        //     vm.startBroadcast(admin);

        //     accounting.revokeRole(accounting.SET_BOND_CURVE_ROLE(), address(module));
        //     module.grantRole(
        //         module.CREATE_NODE_OPERATOR_ROLE(),
        //         deploymentConfig.permissionlessGate
        //     );
        //     module.grantRole(
        //         module.CREATE_NODE_OPERATOR_ROLE(),
        //         deploymentConfig.vettedGate
        //     );
        //     accounting.grantRole(
        //         accounting.SET_BOND_CURVE_ROLE(),
        //         deploymentConfig.vettedGate
        //     );

        // address generalDelayedPenaltyReporter = module.getRoleMember(
        //     REPORT_EL_REWARDS_STEALING_PENALTY_ROLE,
        //     1
        // );
        // module.revokeRole(
        //     REPORT_EL_REWARDS_STEALING_PENALTY_ROLE,
        //     generalDelayedPenaltyReporter
        // );
        // module.grantRole(
        //     REPORT_GENERAL_DELAYED_PENALTY_ROLE,
        //     generalDelayedPenaltyReporter
        // );
        //
        // address generalDelayedPenaltySettler = module.getRoleMember(
        //     SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE,
        //     1
        // );
        // module.revokeRole(
        //     SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE,
        //     generalDelayedPenaltySettler
        // );
        // module.grantRole(
        //     SETTLE_GENERAL_DELAYED_PENALTY_ROLE,
        //     generalDelayedPenaltySettler
        // );

        //     accounting.grantRole(accounting.MANAGE_BOND_CURVES_ROLE(), admin);

        //     accounting.addBondCurve(identifiedCommunityStakersGateBondCurve);

        //     accounting.revokeRole(accounting.MANAGE_BOND_CURVES_ROLE(), admin);

        //     module.revokeRole(module.VERIFIER_ROLE(), address(deploymentConfig.verifier));
        //     module.grantRole(
        //         module.VERIFIER_ROLE(),
        //         address(deploymentConfig.verifierV2)
        //     );
        //     TODO: Grant VERIFIER_ROLE on CSModule to EasyTrack executor.

        //     module.revokeRole(module.PAUSE_ROLE(), address(deploymentConfig.gateSeal));
        //     accounting.revokeRole(
        //         accounting.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSeal)
        //     );
        //     oracle.revokeRole(
        //         oracle.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSeal)
        //     );

        //     module.grantRole(module.PAUSE_ROLE(), address(deploymentConfig.gateSealV2));
        //     accounting.grantRole(
        //         accounting.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSealV2)
        //     );
        //     oracle.grantRole(
        //         oracle.PAUSE_ROLE(),
        //         address(deploymentConfig.gateSealV2)
        //     );

        //     module.grantRole(module.PAUSE_ROLE(), deployParams.resealManager);
        //     module.grantRole(module.RESUME_ROLE(), deployParams.resealManager);
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

        //     accounting.revokeRole(keccak256("RESET_BOND_CURVE_ROLE"), address(module));
        //     address moduleCommittee = accounting.getRoleMember(
        //         keccak256("RESET_BOND_CURVE_ROLE"),
        //         0
        //     );
        //     accounting.revokeRole(
        //         keccak256("RESET_BOND_CURVE_ROLE"),
        //         address(moduleCommittee)
        //     );

        //     vm.stopBroadcast();
    }
}
