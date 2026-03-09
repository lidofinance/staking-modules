// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

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

import { ForkHelpersCommon } from "./Common.sol";
import { DeployParams } from "../csm/DeployBase.s.sol";

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

        vm.stopBroadcast();
    }

    /// @dev Simulation helper only.
    ///      In a real governance vote, all steps below are expected to be executed atomically
    ///      in a single transaction via a temporary vote executor contract.
    function addCuratedModule() external {
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) revert WrongModuleType();

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

        burner.grantRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting));

        twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), address(ejector));

        curatedModule.grantRole(curatedModule.RESUME_ROLE(), agent);
        curatedModule.resume();
        curatedModule.revokeRole(curatedModule.RESUME_ROLE(), agent);
        hashConsensus.updateInitialEpoch(47480);

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
        {
            string memory deploymentConfigContent = vm.readFile(env.DEPLOY_CONFIG);
            deploymentConfig = parseDeploymentConfig(deploymentConfigContent);
            deployParams = parseDeployParams(env.DEPLOY_CONFIG);
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
            // 4-5. Upgrade and finalize FeeOracle v3 in a single tx
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

            // 13. Point ValidatorStrikes to the new Ejector
            strikes.setEjector(deploymentConfig.ejector);

            // 14. Grant REPORT_GENERAL_DELAYED_PENALTY_ROLE
            module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.generalDelayedPenaltyReporter);
            // 15. Grant SETTLE_GENERAL_DELAYED_PENALTY_ROLE
            module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.easyTrackEVMScriptExecutor);
            // 16. Revoke REPORT_EL_REWARDS_STEALING_PENALTY_ROLE
            module.revokeRole(REPORT_EL_REWARDS_STEALING_PENALTY_ROLE, deployParams.generalDelayedPenaltyReporter);
            // 17. Revoke SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE
            module.revokeRole(SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE, deployParams.easyTrackEVMScriptExecutor);
            // 18. Revoke VERIFIER_ROLE from previous verifier
            module.revokeRole(module.VERIFIER_ROLE(), deploymentConfig.verifier);
            // 19. Grant VERIFIER_ROLE to VerifierV3
            module.grantRole(module.VERIFIER_ROLE(), deploymentConfig.verifierV3);
            // 20. Grant REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE to VerifierV3
            module.grantRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), deploymentConfig.verifierV3);
            // 21. Grant REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE to Easy Track
            module.grantRole(
                module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(),
                deployParams.easyTrackEVMScriptExecutor
            );
            // 22. Revoke CREATE_NODE_OPERATOR_ROLE from old PermissionlessGate
            module.revokeRole(module.CREATE_NODE_OPERATOR_ROLE(), oldPermissionlessGate);
            // 23. Grant CREATE_NODE_OPERATOR_ROLE to new PermissionlessGate
            module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), deploymentConfig.permissionlessGate);

            // 24. Revoke PAUSE_ROLE from old gate seal on CSModule
            module.revokeRole(module.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 25. Revoke PAUSE_ROLE from old gate seal on Accounting
            accounting.revokeRole(accounting.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 26. Revoke PAUSE_ROLE from old gate seal on FeeOracle
            oracle.revokeRole(oracle.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 27. Revoke PAUSE_ROLE from old gate seal on VettedGate
            existingVettedGate.revokeRole(existingVettedGate.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 28. Revoke PAUSE_ROLE from old gate seal on old Verifier
            oldVerifier.revokeRole(oldVerifier.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 29. Revoke PAUSE_ROLE from old gate seal on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.PAUSE_ROLE(), deploymentConfig.gateSeal);
            // 30. Revoke PAUSE_ROLE from reseal manager on old Verifier
            oldVerifier.revokeRole(oldVerifier.PAUSE_ROLE(), deployParams.resealManager);
            // 31. Revoke RESUME_ROLE from reseal manager on old Verifier
            oldVerifier.revokeRole(oldVerifier.RESUME_ROLE(), deployParams.resealManager);
            // 32. Revoke PAUSE_ROLE from reseal manager on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.PAUSE_ROLE(), deployParams.resealManager);
            // 33. Revoke RESUME_ROLE from reseal manager on old Ejector
            oldEjectorContract.revokeRole(oldEjectorContract.RESUME_ROLE(), deployParams.resealManager);

            // Revoke legacy referral program roles.
            existingVettedGate.revokeRole(START_REFERRAL_SEASON_ROLE, deployParams.aragonAgent);
            existingVettedGate.revokeRole(END_REFERRAL_SEASON_ROLE, deployParams.identifiedCommunityStakersGateManager);

            // 34. Grant PAUSE_ROLE to gateSealV3 on CSModule
            module.grantRole(module.PAUSE_ROLE(), deploymentConfig.gateSealV3);
            // 35. Grant PAUSE_ROLE to gateSealV3 on Accounting
            accounting.grantRole(accounting.PAUSE_ROLE(), deploymentConfig.gateSealV3);
            // 36. Grant PAUSE_ROLE to gateSealV3 on FeeOracle
            oracle.grantRole(oracle.PAUSE_ROLE(), deploymentConfig.gateSealV3);
            // 37. Grant PAUSE_ROLE to gateSealV3 on VettedGate
            existingVettedGate.grantRole(existingVettedGate.PAUSE_ROLE(), deploymentConfig.gateSealV3);
            // 38. Grant MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE to penaltiesManager
            parametersRegistry.grantRole(
                parametersRegistry.MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE(),
                deployParams.penaltiesManager
            );

            vm.stopBroadcast();
        }

        {
            vm.startBroadcast(burnerAdmin);
            // 39. Revoke REQUEST_BURN_SHARES_ROLE from Accounting
            burner.revokeRole(burner.REQUEST_BURN_SHARES_ROLE(), address(accounting));
            // 40. Grant REQUEST_BURN_MY_STETH_ROLE to Accounting
            burner.grantRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting));
            vm.stopBroadcast();
        }

        {
            ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(
                locator.triggerableWithdrawalsGateway()
            );
            address twgAdmin = _prepareAdmin(address(twg));

            vm.startBroadcast(twgAdmin);
            // 41. Revoke TWG full-withdrawal role from old Ejector
            twg.revokeRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), oldEjector);
            // 42. Grant TWG full-withdrawal role to new Ejector
            twg.grantRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), deploymentConfig.ejector);
            vm.stopBroadcast();
        }
    }
}
