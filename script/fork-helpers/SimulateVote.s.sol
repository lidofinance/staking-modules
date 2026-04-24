// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { CSModule } from "../../src/CSModule.sol";
import { Accounting } from "../../src/Accounting.sol";
import { Ejector } from "../../src/Ejector.sol";
import { FeeDistributor } from "../../src/FeeDistributor.sol";
import { ParametersRegistry } from "../../src/ParametersRegistry.sol";
import { FeeOracle } from "../../src/FeeOracle.sol";
import { ValidatorStrikes } from "../../src/ValidatorStrikes.sol";
import { Verifier } from "../../src/Verifier.sol";
import { VettedGate } from "../../src/VettedGate.sol";
import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ITriggerableWithdrawalsGateway } from "../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";
import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";

import { ICircuitBreaker } from "../../src/interfaces/ICircuitBreaker.sol";
import { ForkHelpersCommon } from "./Common.sol";
import { DeployParams } from "../csm/DeployBase.s.sol";
import { DeployCSM0x02Params } from "../csm0x02/DeployCSM0x02Base.s.sol";
import { CuratedDeployParams } from "../curated/DeployBase.s.sol";

contract SimulateVote is Script, ForkHelpersCommon {
    bytes32 internal constant REPORT_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("REPORT_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 internal constant SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 internal constant START_REFERRAL_SEASON_ROLE = keccak256("START_REFERRAL_SEASON_ROLE");
    bytes32 internal constant END_REFERRAL_SEASON_ROLE = keccak256("END_REFERRAL_SEASON_ROLE");

    error WrongModuleType();

    /// @dev Simulation helper only.
    ///      In a real governance vote, all steps below are expected to be executed atomically
    ///      in a single transaction via a temporary vote executor contract.
    function addModule() external {
        _setUp();
        if (moduleType != ModuleType.Community && moduleType != ModuleType.Community0x02) {
            revert WrongModuleType();
        }

        Env memory env = envVars();
        address cbPauser;
        if (moduleType == ModuleType.Community) {
            cbPauser = parseDeployParams(env.DEPLOY_CONFIG).circuitBreakerPauser;
        } else {
            cbPauser = parseDeployParams0x02(env.DEPLOY_CONFIG).circuitBreakerPauser;
        }

        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        IBurner burner = IBurner(locator.burner());
        ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(locator.triggerableWithdrawalsGateway());

        address agent = stakingRouter.getRoleMember(stakingRouter.STAKING_MODULE_MANAGE_ROLE(), 0);
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
        burner.grantRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting));
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
        // 8-13. Register pausers in CircuitBreaker
        if (address(circuitBreaker).code.length > 0) {
            circuitBreaker.registerPauser(address(module), cbPauser);
            circuitBreaker.registerPauser(address(accounting), cbPauser);
            circuitBreaker.registerPauser(address(oracle), cbPauser);
            circuitBreaker.registerPauser(address(verifier), cbPauser);
            circuitBreaker.registerPauser(address(ejector), cbPauser);
            if (moduleType == ModuleType.Community) {
                // VettedGate pauser (Community0x02 has no VettedGate)
                circuitBreaker.registerPauser(address(vettedGate), cbPauser);
            }
        }

        vm.stopBroadcast();
    }

    /// @dev Simulation helper only.
    ///      In a real governance vote, all steps below are expected to be executed atomically
    ///      in a single transaction via a temporary vote executor contract.
    function addCuratedModule() external {
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) revert WrongModuleType();

        Env memory env = envVars();
        address cbPauser = parseCuratedDeployParams(env.DEPLOY_CONFIG).circuitBreakerPauser;

        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        IBurner burner = IBurner(locator.burner());
        ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(locator.triggerableWithdrawalsGateway());

        address agent = stakingRouter.getRoleMember(stakingRouter.STAKING_MODULE_MANAGE_ROLE(), 0);
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

        // 1. Add Curated module
        stakingRouter.addStakingModule({
            _name: "curated-onchain-v2",
            _stakingModuleAddress: address(curatedModule),
            _stakeShareLimit: 2000, // 20%
            _priorityExitShareThreshold: 2500, // 25%
            _stakingModuleFee: 400, // 4%
            _treasuryFee: 600, // 6%
            _maxDepositsPerBlock: 30,
            _minDepositBlockDistance: 25
        });

        // 2. burner role
        burner.grantRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting));

        // 3. twg role
        twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), address(ejector));

        // 4. Grant resume to agent
        curatedModule.grantRole(curatedModule.RESUME_ROLE(), agent);
        // 5. Resume Curated module
        curatedModule.resume();
        // 6. Revoke resume
        curatedModule.revokeRole(curatedModule.RESUME_ROLE(), agent);
        // 7. Update initial epoch
        hashConsensus.updateInitialEpoch(47480);
        // 8-12. Register pausers in CircuitBreaker
        if (address(circuitBreaker).code.length > 0) {
            circuitBreaker.registerPauser(address(curatedModule), cbPauser);
            circuitBreaker.registerPauser(address(accounting), cbPauser);
            circuitBreaker.registerPauser(address(oracle), cbPauser);
            circuitBreaker.registerPauser(address(verifier), cbPauser);
            circuitBreaker.registerPauser(address(ejector), cbPauser);
        }

        vm.stopBroadcast();
    }

    /// @dev Simulation helper only.
    ///      In a real governance vote, all steps below are expected to be executed atomically
    ///      in a single transaction via a temporary vote executor contract.
    function upgrade() external {
        _setUp();
        if (moduleType != ModuleType.Community) revert WrongModuleType();

        Env memory env = envVars();
        DeploymentConfig memory deploymentConfig;
        DeployParams memory deployParams;
        address gateSeal;
        {
            string memory deploymentConfigContent = vm.readFile(env.DEPLOY_CONFIG);
            deploymentConfig = parseDeploymentConfig(deploymentConfigContent);
            deployParams = parseDeployParams(env.DEPLOY_CONFIG);
            gateSeal = vm.parseJsonAddress(deploymentConfigContent, ".GateSeal");
        }
        VettedGate existingVettedGate = VettedGate(deploymentConfig.vettedGate);
        address admin = _prepareAdmin(deploymentConfig.csm);
        IBurner burner = IBurner(locator.burner());
        address burnerAdmin = _prepareAdmin(address(burner));

        {
            OssifiableProxy moduleProxy = OssifiableProxy(payable(deploymentConfig.csm));
            vm.startBroadcast(_prepareProxyAdmin(address(moduleProxy)));
            // 1-2. Upgrade and finalize CSModule v3 in a single tx
            moduleProxy.proxy__upgradeToAndCall(
                deploymentConfig.csmImpl,
                abi.encodeCall(CSModule.finalizeUpgradeV3, ())
            );
            vm.stopBroadcast();
        }

        {
            OssifiableProxy parametersRegistryProxy = OssifiableProxy(payable(deploymentConfig.parametersRegistry));
            vm.startBroadcast(_prepareProxyAdmin(address(parametersRegistryProxy)));
            // 3-4. Upgrade and finalize ParametersRegistry v3 in a single tx
            parametersRegistryProxy.proxy__upgradeToAndCall(
                deploymentConfig.parametersRegistryImpl,
                abi.encodeCall(ParametersRegistry.finalizeUpgradeV3, ())
            );
            vm.stopBroadcast();
        }
        {
            OssifiableProxy oracleProxy = OssifiableProxy(payable(deploymentConfig.oracle));
            vm.startBroadcast(_prepareProxyAdmin(address(oracleProxy)));
            // 5-6. Upgrade and finalize FeeOracle v3 in a single tx
            oracleProxy.proxy__upgradeToAndCall(
                deploymentConfig.oracleImpl,
                abi.encodeCall(FeeOracle.finalizeUpgradeV3, (deployParams.consensusVersion))
            );
            vm.stopBroadcast();
        }

        {
            OssifiableProxy vettedGateProxy = OssifiableProxy(payable(deploymentConfig.vettedGate));
            vm.startBroadcast(_prepareProxyAdmin(address(vettedGateProxy)));
            // 6. Upgrade VettedGate implementation
            vettedGateProxy.proxy__upgradeTo(deploymentConfig.vettedGateImpl);
            vm.stopBroadcast();
        }

        {
            OssifiableProxy accountingProxy = OssifiableProxy(payable(deploymentConfig.accounting));
            vm.startBroadcast(_prepareProxyAdmin(address(accountingProxy)));
            // 7-8. Upgrade and finalize Accounting v3 in a single tx
            accountingProxy.proxy__upgradeToAndCall(
                deploymentConfig.accountingImpl,
                abi.encodeCall(Accounting.finalizeUpgradeV3, ())
            );
            vm.stopBroadcast();
        }

        {
            OssifiableProxy feeDistributorProxy = OssifiableProxy(payable(deploymentConfig.feeDistributor));
            vm.startBroadcast(_prepareProxyAdmin(address(feeDistributorProxy)));
            // 9-10. Upgrade and finalize FeeDistributor v3 in a single tx
            feeDistributorProxy.proxy__upgradeToAndCall(
                deploymentConfig.feeDistributorImpl,
                abi.encodeCall(FeeDistributor.finalizeUpgradeV3, ())
            );
            vm.stopBroadcast();
        }

        {
            OssifiableProxy exitPenaltiesProxy = OssifiableProxy(payable(deploymentConfig.exitPenalties));
            vm.startBroadcast(_prepareProxyAdmin(address(exitPenaltiesProxy)));
            // 11. Upgrade ExitPenalties implementation
            exitPenaltiesProxy.proxy__upgradeTo(deploymentConfig.exitPenaltiesImpl);
            vm.stopBroadcast();
        }

        {
            OssifiableProxy strikesProxy = OssifiableProxy(payable(deploymentConfig.strikes));
            vm.startBroadcast(_prepareProxyAdmin(address(strikesProxy)));
            // 12. Upgrade ValidatorStrikes implementation
            strikesProxy.proxy__upgradeTo(deploymentConfig.strikesImpl);
            vm.stopBroadcast();
        }

        module = CSModule(deploymentConfig.csm);
        accounting = Accounting(deploymentConfig.accounting);
        strikes = ValidatorStrikes(deploymentConfig.strikes);

        address oldPermissionlessGate = module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0);
        if (oldPermissionlessGate == address(existingVettedGate)) {
            oldPermissionlessGate = module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 1);
        }
        address oldEjector = address(strikes.ejector());
        {
            Verifier oldVerifier = Verifier(deploymentConfig.verifier);
            Ejector oldEjectorContract = Ejector(oldEjector);

            vm.startBroadcast(admin);

            // 14. Point ValidatorStrikes to the new Ejector
            strikes.setEjector(deploymentConfig.ejector);

            // 15. Grant REPORT_GENERAL_DELAYED_PENALTY_ROLE
            module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.generalDelayedPenaltyReporter);
            // 16. Grant SETTLE_GENERAL_DELAYED_PENALTY_ROLE
            module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.easyTrackEVMScriptExecutor);
            // 17. Revoke REPORT_EL_REWARDS_STEALING_PENALTY_ROLE
            module.revokeRole(REPORT_EL_REWARDS_STEALING_PENALTY_ROLE, deployParams.generalDelayedPenaltyReporter);
            // 18. Revoke SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE
            module.revokeRole(SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE, deployParams.easyTrackEVMScriptExecutor);
            // 19. Revoke VERIFIER_ROLE from previous verifier
            module.revokeRole(module.VERIFIER_ROLE(), deploymentConfig.verifier);
            // 20. Grant VERIFIER_ROLE to VerifierV3
            module.grantRole(module.VERIFIER_ROLE(), deploymentConfig.verifierV3);
            // 21. Grant REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE to VerifierV3
            module.grantRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), deploymentConfig.verifierV3);
            // 22. Grant REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE to Easy Track
            module.grantRole(
                module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(),
                deployParams.easyTrackEVMScriptExecutor
            );
            // 23. Revoke CREATE_NODE_OPERATOR_ROLE from old PermissionlessGate
            module.revokeRole(module.CREATE_NODE_OPERATOR_ROLE(), oldPermissionlessGate);
            // 24. Grant CREATE_NODE_OPERATOR_ROLE to new PermissionlessGate
            module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), deploymentConfig.permissionlessGate);

            // NOTE: Revoking old gate seal PAUSE_ROLE on CSModule, Accounting, FeeOracle, VettedGate
            // is handled in a separate intermediate vote.
            // Here we only revoke roles on replaced contracts (old Verifier and old Ejector).
            // 25. Revoke PAUSE_ROLE from old gate seal on old Verifier
            oldVerifier.revokeRole(oldVerifier.PAUSE_ROLE(), gateSeal);
            // 26. Revoke PAUSE_ROLE from old gate seal on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.PAUSE_ROLE(), gateSeal);
            // 27. Revoke PAUSE_ROLE from reseal manager on old Verifier
            oldVerifier.revokeRole(oldVerifier.PAUSE_ROLE(), deployParams.resealManager);
            // 28. Revoke RESUME_ROLE from reseal manager on old Verifier
            oldVerifier.revokeRole(oldVerifier.RESUME_ROLE(), deployParams.resealManager);
            // 29. Revoke PAUSE_ROLE from reseal manager on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.PAUSE_ROLE(), deployParams.resealManager);
            // 30. Revoke RESUME_ROLE from reseal manager on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.RESUME_ROLE(), deployParams.resealManager);

            // 31-32. Revoke legacy referral program roles
            existingVettedGate.revokeRole(START_REFERRAL_SEASON_ROLE, deployParams.aragonAgent);
            existingVettedGate.revokeRole(END_REFERRAL_SEASON_ROLE, deployParams.identifiedCommunityStakersGateManager);

            // 33-42. Setup CircuitBreaker: grant PAUSE_ROLE and register pausers
            if (deploymentConfig.circuitBreaker != address(0)) {
                module.grantRole(module.PAUSE_ROLE(), deploymentConfig.circuitBreaker);
                accounting.grantRole(accounting.PAUSE_ROLE(), deploymentConfig.circuitBreaker);
                oracle.grantRole(oracle.PAUSE_ROLE(), deploymentConfig.circuitBreaker);
                existingVettedGate.grantRole(existingVettedGate.PAUSE_ROLE(), deploymentConfig.circuitBreaker);

                if (deploymentConfig.circuitBreaker.code.length > 0) {
                    ICircuitBreaker cb = ICircuitBreaker(deploymentConfig.circuitBreaker);
                    cb.registerPauser(address(module), deployParams.circuitBreakerPauser);
                    cb.registerPauser(address(accounting), deployParams.circuitBreakerPauser);
                    cb.registerPauser(address(oracle), deployParams.circuitBreakerPauser);
                    cb.registerPauser(address(existingVettedGate), deployParams.circuitBreakerPauser);
                    cb.registerPauser(deploymentConfig.verifierV3, deployParams.circuitBreakerPauser);
                    cb.registerPauser(deploymentConfig.ejector, deployParams.circuitBreakerPauser);
                } else {
                    console.log("CircuitBreaker is EOA, skipping registering pausers");
                }
            } else {
                console.log("CircuitBreaker is not configured");
            }
            // 43. Grant MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE to penaltiesManager
            parametersRegistry.grantRole(
                parametersRegistry.MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE(),
                deployParams.penaltiesManager
            );

            vm.stopBroadcast();
        }

        {
            vm.startBroadcast(burnerAdmin);
            // 44. Revoke REQUEST_BURN_SHARES_ROLE from Accounting
            burner.revokeRole(burner.REQUEST_BURN_SHARES_ROLE(), address(accounting));
            // 45. Grant REQUEST_BURN_MY_STETH_ROLE to Accounting
            burner.grantRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting));
            vm.stopBroadcast();
        }

        {
            ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(
                locator.triggerableWithdrawalsGateway()
            );
            address twgAdmin = _prepareAdmin(address(twg));

            vm.startBroadcast(twgAdmin);
            // 46. Revoke TWG full-withdrawal role from old Ejector
            twg.revokeRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), oldEjector);
            // 47. Grant TWG full-withdrawal role to new Ejector
            twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), deploymentConfig.ejector);
            vm.stopBroadcast();
        }
    }

    /// @dev Simulation helper only. Executes post-vote state preparation that is not part of the vote payload.
    function postUpgrade() external {
        _setUp();
        if (moduleType != ModuleType.Community) revert WrongModuleType();

        vm.startBroadcast(_prepareAdmin(address(module)));
        module.rebuildTotalWithdrawnValidators();
        vm.stopBroadcast();
    }
}
