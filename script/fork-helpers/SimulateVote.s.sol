// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { BaseModule } from "../../src/abstract/BaseModule.sol";
import { CuratedModule } from "../../src/CuratedModule.sol";
import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ITriggerableWithdrawalsGateway } from "../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";

import { ICircuitBreaker } from "../../src/interfaces/ICircuitBreaker.sol";
import { GloasVerifierSwap, VoteConfig } from "../utils/Votes.sol";
import { DualGovernance } from "../utils/DualGovernance.sol";
import { JsonBindings } from "../utils/JsonBindings.sol";
import { ForkHelpersCommon } from "./Common.sol";

contract SimulateVote is Script, ForkHelpersCommon {
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
            _stakingModuleConfig: IStakingRouter.StakingModuleConfig({
                stakeShareLimit: 2000, // 20%
                priorityExitShareThreshold: 2500, // 25%
                stakingModuleFee: 800, // 8%
                treasuryFee: 200, // 2%
                maxDepositsPerBlock: 30,
                minDepositBlockDistance: 25,
                withdrawalCredentialsType: moduleType == ModuleType.Community ? 0x01 : 0x02
            })
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
        // 8-14. Register pausers in CircuitBreaker
        circuitBreaker.registerPauser(address(module), cbPauser);
        circuitBreaker.registerPauser(address(accounting), cbPauser);
        circuitBreaker.registerPauser(address(oracle), cbPauser);
        circuitBreaker.registerPauser(address(verifier), cbPauser);
        circuitBreaker.registerPauser(address(ejector), cbPauser);
        if (moduleType == ModuleType.Community) {
            // VettedGate pauser (Community0x02 has no VettedGate)
            circuitBreaker.registerPauser(address(vettedGate), cbPauser);
            circuitBreaker.registerPauser(address(identifiedDVTClusterGate), cbPauser);
        }

        if (moduleType == ModuleType.Community0x02) {
            (, uint256 topUpQueueLimit, , ) = module.getTopUpQueue();
            // Hoodi and local-devnet deployments already use this limit.
            if (topUpQueueLimit != 32) {
                module.grantRole(module.MANAGE_TOP_UP_QUEUE_ROLE(), agent);
                module.setTopUpQueueLimit(32);
                module.revokeRole(module.MANAGE_TOP_UP_QUEUE_ROLE(), agent);
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
            _stakingModuleConfig: IStakingRouter.StakingModuleConfig({
                stakeShareLimit: 2000, // 20%
                priorityExitShareThreshold: 2500, // 25%
                stakingModuleFee: 400, // 4%
                treasuryFee: 600, // 6%
                maxDepositsPerBlock: 30,
                minDepositBlockDistance: 25,
                withdrawalCredentialsType: 0x02
            })
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
        circuitBreaker.registerPauser(address(curatedModule), cbPauser);
        circuitBreaker.registerPauser(address(accounting), cbPauser);
        circuitBreaker.registerPauser(address(oracle), cbPauser);
        circuitBreaker.registerPauser(address(verifier), cbPauser);
        circuitBreaker.registerPauser(address(ejector), cbPauser);

        vm.stopBroadcast();
    }

    /// @dev Simulation helper only.
    ///      In a real governance vote, all steps below are expected to be executed atomically
    ///      in a single transaction via a temporary vote executor contract.
    ///      Does nothing once the vote's Dual Governance proposal is executed.
    function run() external {
        string memory path = vm.envString("VOTE_CONFIG");
        if (!vm.isFile(path)) {
            console.log("No pending vote at", path);
            return;
        }

        VoteConfig memory vote = JsonBindings.deserializeVoteConfig(vm.readFile(path));
        if (DualGovernance.isProposalExecuted(vote.dgTimelock, vote.dgProposalId)) {
            console.log("Dual Governance proposal is executed, nothing to simulate:", vote.dgProposalId);
            return;
        }

        for (uint256 i; i < vote.gloasVerifiers.length; ++i) {
            _swapGloasVerifier(vote.gloasVerifiers[i]);
        }
    }

    function _swapGloasVerifier(GloasVerifierSwap memory swap) internal {
        BaseModule module = BaseModule(swap.module);
        ICircuitBreaker cb = ICircuitBreaker(swap.circuitBreaker);
        address pauser = cb.getPauser(swap.oldVerifier);

        vm.startBroadcast(_prepareAdmin(address(module)));
        // 1. Revoke VERIFIER_ROLE from the previous Verifier
        module.revokeRole(module.VERIFIER_ROLE(), swap.oldVerifier);
        // 2. Revoke REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE from the previous Verifier
        module.revokeRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), swap.oldVerifier);
        // 3. Grant VERIFIER_ROLE to the new Verifier
        module.grantRole(module.VERIFIER_ROLE(), swap.newVerifier);
        // 4. Grant REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE to the new Verifier
        module.grantRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), swap.newVerifier);
        // 5. Register the new Verifier in CircuitBreaker with the pauser of the previous one
        cb.registerPauser(swap.newVerifier, pauser);
        // 6. Unregister the previous Verifier from CircuitBreaker (a zero pauser removes it)
        cb.registerPauser(swap.oldVerifier, address(0));
        vm.stopBroadcast();
    }
}
