// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { OssifiableProxy } from "../../../src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "../../../src/CSModule.sol";
import { Accounting } from "../../../src/Accounting.sol";
import { HashConsensus } from "../../../src/lib/base-oracle/HashConsensus.sol";
import { FeeDistributor } from "../../../src/FeeDistributor.sol";
import { FeeOracle } from "../../../src/FeeOracle.sol";
import { ValidatorStrikes } from "../../../src/ValidatorStrikes.sol";
import { IWithdrawalQueue } from "../../../src/interfaces/IWithdrawalQueue.sol";
import { IBondCurve } from "../../../src/interfaces/IBondCurve.sol";
import { BaseOracle } from "../../../src/lib/base-oracle/BaseOracle.sol";
import { GIndex } from "../../../src/lib/GIndex.sol";
import { Slot } from "../../../src/lib/Types.sol";
import { Versioned } from "../../../src/lib/utils/Versioned.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    CommonDeployParams internal deployParams;
    uint256 adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        deployParams = parseCommonDeployParams(config);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_state_scratch_onlyFull() public view {
        assertTrue(module.isPaused());
        assertEq(module.getNodeOperatorsCount(), 0);
        assertEq(module.getNonce(), 0);
    }

    function test_state_afterVote() public view {
        assertFalse(module.isPaused());
    }

    function test_state_onlyFull() public view {
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_immutables() public view {
        assertEq(moduleImpl.getType(), deployParams.moduleType);
        assertEq(
            address(moduleImpl.LIDO_LOCATOR()),
            deployParams.lidoLocatorAddress
        );
        assertEq(
            address(moduleImpl.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
        assertEq(address(moduleImpl.STETH()), address(lido));
        assertEq(address(moduleImpl.ACCOUNTING()), address(accounting));
        assertEq(address(moduleImpl.EXIT_PENALTIES()), address(exitPenalties));
        assertEq(
            address(moduleImpl.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
    }

    function test_roles_onlyFull() public view {
        assertTrue(
            module.hasRole(
                module.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertTrue(
            module.getRoleMemberCount(module.DEFAULT_ADMIN_ROLE()) ==
                adminsCount
        );

        assertTrue(
            module.hasRole(
                module.STAKING_ROUTER_ROLE(),
                locator.stakingRouter()
            )
        );
        assertEq(module.getRoleMemberCount(module.STAKING_ROUTER_ROLE()), 1);

        assertTrue(module.hasRole(module.PAUSE_ROLE(), address(gateSeal)));
        assertTrue(
            module.hasRole(module.PAUSE_ROLE(), deployParams.resealManager)
        );
        assertEq(module.getRoleMemberCount(module.PAUSE_ROLE()), 2);

        assertTrue(
            module.hasRole(module.RESUME_ROLE(), deployParams.resealManager)
        );
        assertEq(module.getRoleMemberCount(module.RESUME_ROLE()), 1);

        assertTrue(
            module.hasRole(
                module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
                address(deployParams.generalDelayedPenaltyReporter)
            )
        );
        assertEq(
            module.getRoleMemberCount(
                module.REPORT_GENERAL_DELAYED_PENALTY_ROLE()
            ),
            1
        );

        assertTrue(
            module.hasRole(
                module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
                address(deployParams.easyTrackEVMScriptExecutor)
            )
        );
        assertEq(
            module.getRoleMemberCount(
                module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE()
            ),
            1
        );

        assertTrue(module.hasRole(module.VERIFIER_ROLE(), address(verifier)));
        assertEq(module.getRoleMemberCount(module.VERIFIER_ROLE()), 1);
        assertTrue(
            module.hasRole(module.SUBMIT_WITHDRAWALS_ROLE(), address(verifier))
        );
        assertTrue(
            module.hasRole(
                module.SUBMIT_WITHDRAWALS_ROLE(),
                address(deployParams.easyTrackEVMScriptExecutor)
            )
        );
        assertEq(
            module.getRoleMemberCount(module.SUBMIT_WITHDRAWALS_ROLE()),
            2
        );

        assertEq(module.getRoleMemberCount(module.RECOVERER_ROLE()), 0);
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: deployParams.aragonAgent });

        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));

        assertEq(proxy.proxy__getImplementation(), address(moduleImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        CSModule moduleImpl = CSModule(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        moduleImpl.initialize({ admin: deployParams.aragonAgent });
    }
}

contract AccountingDeploymentTest is DeploymentBaseTest {
    function test_state_scratch_onlyFull() public view {
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_state_onlyFull() public view {
        assertEq(accounting.DEFAULT_BOND_CURVE_ID(), 0);

        assertEq(
            address(accounting.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
        assertEq(accounting.getBondLockPeriod(), deployParams.bondLockPeriod);

        assertEq(
            accounting.chargePenaltyRecipient(),
            deployParams.chargePenaltyRecipient
        );
        IWithdrawalQueue wq = IWithdrawalQueue(locator.withdrawalQueue());
        assertEq(
            lido.allowance(address(accounting), wq.WSTETH()),
            type(uint256).max
        );
        assertEq(
            lido.allowance(address(accounting), address(wq)),
            type(uint256).max
        );
        assertEq(
            lido.allowance(address(accounting), locator.burner()),
            type(uint256).max
        );
        assertEq(accounting.getInitializedVersion(), 3);
    }

    function test_state() public view {
        assertFalse(accounting.isPaused());
    }

    function test_immutables() public view {
        assertEq(address(accountingImpl.MODULE()), address(module));
        assertEq(address(accountingImpl.LIDO_LOCATOR()), address(locator));
        assertEq(address(accountingImpl.LIDO()), locator.lido());
        assertEq(
            address(accountingImpl.WITHDRAWAL_QUEUE()),
            locator.withdrawalQueue()
        );
        assertEq(
            address(accountingImpl.WSTETH()),
            IWithdrawalQueue(locator.withdrawalQueue()).WSTETH()
        );

        assertEq(
            accountingImpl.MIN_BOND_LOCK_PERIOD(),
            deployParams.minBondLockPeriod
        );
        assertEq(
            accountingImpl.MAX_BOND_LOCK_PERIOD(),
            deployParams.maxBondLockPeriod
        );
        assertEq(
            address(accountingImpl.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
    }

    function test_roles_onlyFull() public view {
        assertTrue(
            accounting.hasRole(
                accounting.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            accounting.getRoleMemberCount(accounting.DEFAULT_ADMIN_ROLE()),
            adminsCount
        );

        assertTrue(
            accounting.hasRole(accounting.PAUSE_ROLE(), address(gateSeal))
        );
        assertTrue(
            accounting.hasRole(
                accounting.PAUSE_ROLE(),
                deployParams.resealManager
            )
        );
        assertEq(accounting.getRoleMemberCount(accounting.PAUSE_ROLE()), 2);

        assertTrue(
            accounting.hasRole(
                accounting.RESUME_ROLE(),
                deployParams.resealManager
            )
        );
        assertEq(accounting.getRoleMemberCount(accounting.RESUME_ROLE()), 1);

        assertTrue(
            accounting.hasRole(
                accounting.SET_BOND_CURVE_ROLE(),
                deployParams.setResetBondCurveAddress
            )
        );
        assertEq(
            accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()),
            2
        );

        assertEq(
            accounting.getRoleMemberCount(keccak256("RESET_BOND_CURVE_ROLE")),
            0
        );

        assertEq(
            accounting.getRoleMemberCount(accounting.MANAGE_BOND_CURVES_ROLE()),
            0
        );

        assertEq(accounting.getRoleMemberCount(accounting.RECOVERER_ROLE()), 0);
    }

    function test_proxy_onlyFull() public {
        IBondCurve.BondCurveIntervalInput[]
            memory defaultBondCurve = new IBondCurve.BondCurveIntervalInput[](
                deployParams.defaultBondCurve.length
            );
        for (uint256 i = 0; i < deployParams.defaultBondCurve.length; i++) {
            defaultBondCurve[i] = IBondCurve.BondCurveIntervalInput({
                minKeysCount: deployParams.defaultBondCurve[i][0],
                trend: deployParams.defaultBondCurve[i][1]
            });
        }

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accounting.initialize({
            bondCurve: defaultBondCurve,
            admin: address(deployParams.aragonAgent),
            bondLockPeriod: deployParams.bondLockPeriod,
            _chargePenaltyRecipient: address(0)
        });

        OssifiableProxy proxy = OssifiableProxy(payable(address(accounting)));

        assertEq(proxy.proxy__getImplementation(), address(accountingImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        Accounting accountingImpl = Accounting(
            proxy.proxy__getImplementation()
        );
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accountingImpl.initialize({
            bondCurve: defaultBondCurve,
            admin: address(deployParams.aragonAgent),
            bondLockPeriod: deployParams.bondLockPeriod,
            _chargePenaltyRecipient: address(0)
        });
    }
}

contract FeeDistributorDeploymentTest is DeploymentBaseTest {
    function test_state_scratch_onlyFull() public view {
        assertEq(feeDistributor.totalClaimableShares(), 0);
        assertEq(feeDistributor.pendingSharesToDistribute(), 0);
        assertEq(feeDistributor.treeRoot(), bytes32(0));
        assertEq(
            keccak256(abi.encodePacked(feeDistributor.treeCid())),
            keccak256("")
        );
    }

    function test_state_onlyFull() public view {
        assertEq(feeDistributor.getInitializedVersion(), 2);
        assertEq(feeDistributor.rebateRecipient(), deployParams.aragonAgent);
    }

    function test_immutables() public view {
        assertEq(address(feeDistributorImpl.STETH()), address(lido));
        assertEq(feeDistributorImpl.ACCOUNTING(), address(accounting));
        assertEq(feeDistributorImpl.ORACLE(), address(oracle));
    }

    function test_roles_onlyFull() public view {
        assertTrue(
            feeDistributor.hasRole(
                feeDistributor.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            feeDistributor.getRoleMemberCount(
                feeDistributor.DEFAULT_ADMIN_ROLE()
            ),
            adminsCount
        );

        assertEq(
            feeDistributor.getRoleMemberCount(feeDistributor.RECOVERER_ROLE()),
            0
        );
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeDistributor.initialize({
            admin: deployParams.aragonAgent,
            _rebateRecipient: deployParams.aragonAgent
        });

        OssifiableProxy proxy = OssifiableProxy(
            payable(address(feeDistributor))
        );

        assertEq(proxy.proxy__getImplementation(), address(feeDistributorImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        FeeDistributor distributorImpl = FeeDistributor(
            proxy.proxy__getImplementation()
        );
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        distributorImpl.initialize({
            admin: deployParams.aragonAgent,
            _rebateRecipient: deployParams.aragonAgent
        });
    }
}

contract FeeOracleDeploymentTest is DeploymentBaseTest {
    function test_state_scratch_onlyFull() public view {
        (
            bytes32 hash,
            uint256 refSlot,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();
        assertEq(hash, bytes32(0));
        assertEq(refSlot, 0);
        assertEq(processingDeadlineTime, 0);
        assertFalse(processingStarted);
        assertEq(oracle.getLastProcessingRefSlot(), 0);
    }

    function test_state_onlyFull() public view {
        assertFalse(oracle.isPaused());
        assertEq(oracle.getContractVersion(), 2);
        assertEq(oracle.getConsensusContract(), address(hashConsensus));
        assertEq(oracle.getConsensusVersion(), deployParams.consensusVersion);
    }

    function test_immutables() public view {
        assertEq(oracleImpl.SECONDS_PER_SLOT(), deployParams.secondsPerSlot);
        assertEq(oracleImpl.GENESIS_TIME(), deployParams.clGenesisTime);
        assertEq(
            address(oracleImpl.FEE_DISTRIBUTOR()),
            address(feeDistributor)
        );
        assertEq(address(oracleImpl.STRIKES()), address(strikes));
    }

    function test_roles_onlyFull() public view {
        assertTrue(
            oracle.hasRole(
                oracle.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            oracle.getRoleMemberCount(oracle.DEFAULT_ADMIN_ROLE()),
            adminsCount
        );

        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), address(gateSeal)));
        assertTrue(
            oracle.hasRole(oracle.PAUSE_ROLE(), deployParams.resealManager)
        );
        assertEq(oracle.getRoleMemberCount(oracle.PAUSE_ROLE()), 2);

        assertTrue(
            oracle.hasRole(oracle.RESUME_ROLE(), deployParams.resealManager)
        );
        assertEq(oracle.getRoleMemberCount(oracle.RESUME_ROLE()), 1);

        assertEq(oracle.getRoleMemberCount(oracle.SUBMIT_DATA_ROLE()), 0);

        assertEq(oracle.getRoleMemberCount(oracle.RECOVERER_ROLE()), 0);

        assertEq(
            oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_CONTRACT_ROLE()),
            0
        );

        assertEq(
            oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_VERSION_ROLE()),
            0
        );
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Versioned.NonZeroContractVersionOnInit.selector);
        oracle.initialize({
            admin: address(deployParams.aragonAgent),
            consensusContract: address(hashConsensus),
            consensusVersion: deployParams.consensusVersion
        });

        OssifiableProxy proxy = OssifiableProxy(payable(address(oracle)));

        assertEq(proxy.proxy__getImplementation(), address(oracleImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        FeeOracle oracleImpl = FeeOracle(proxy.proxy__getImplementation());
        vm.expectRevert(Versioned.NonZeroContractVersionOnInit.selector);
        oracleImpl.initialize({
            admin: address(deployParams.aragonAgent),
            consensusContract: address(hashConsensus),
            consensusVersion: deployParams.consensusVersion
        });
    }
}

contract HashConsensusDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = hashConsensus.getChainConfig();
        assertEq(slotsPerEpoch, deployParams.slotsPerEpoch);
        assertEq(secondsPerSlot, deployParams.secondsPerSlot);
        assertEq(genesisTime, deployParams.clGenesisTime);

        (, uint256 epochsPerFrame, uint256 fastLaneLengthSlots) = hashConsensus
            .getFrameConfig();
        assertEq(epochsPerFrame, deployParams.oracleReportEpochsPerFrame);
        assertEq(fastLaneLengthSlots, deployParams.fastLaneLengthSlots);
        assertEq(hashConsensus.getReportProcessor(), address(oracle));
        assertEq(hashConsensus.getQuorum(), deployParams.hashConsensusQuorum);
        (address[] memory members, ) = hashConsensus.getMembers();
        assertEq(
            keccak256(abi.encode(members)),
            keccak256(abi.encode(deployParams.oracleMembers))
        );

        // For test purposes AO and CSM Oracle members might be different on Hoodi testnet (chainId = 560048)
        if (block.chainid != 560048) {
            (address[] memory membersAo, ) = HashConsensus(
                BaseOracle(locator.accountingOracle()).getConsensusContract()
            ).getMembers();
            assertEq(
                keccak256(abi.encode(membersAo)),
                keccak256(abi.encode(members))
            );
        }
    }

    function test_roles() public view {
        assertTrue(
            hashConsensus.hasRole(
                hashConsensus.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            hashConsensus.getRoleMemberCount(
                hashConsensus.DEFAULT_ADMIN_ROLE()
            ),
            adminsCount
        );

        assertEq(
            hashConsensus.getRoleMemberCount(
                hashConsensus.DISABLE_CONSENSUS_ROLE()
            ),
            0
        );

        assertEq(
            hashConsensus.getRoleMemberCount(
                hashConsensus.MANAGE_REPORT_PROCESSOR_ROLE()
            ),
            0
        );

        // Roles on Hoodi are custom
        if (block.chainid != 560048) {
            assertTrue(
                hashConsensus.hasRole(
                    hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(),
                    deployParams.aragonAgent
                )
            );
            assertEq(
                hashConsensus.getRoleMemberCount(
                    hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE()
                ),
                1
            );

            assertEq(
                hashConsensus.getRoleMemberCount(
                    hashConsensus.MANAGE_FRAME_CONFIG_ROLE()
                ),
                0
            );
            assertEq(
                hashConsensus.getRoleMemberCount(
                    hashConsensus.MANAGE_FAST_LANE_CONFIG_ROLE()
                ),
                0
            );
        }
    }
}

contract VerifierDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        assertFalse(verifier.isPaused());
    }

    function test_immutables() public view {
        assertEq(verifier.WITHDRAWAL_ADDRESS(), locator.withdrawalVault());
        assertEq(address(verifier.MODULE()), address(module));
        assertEq(verifier.SLOTS_PER_EPOCH(), deployParams.slotsPerEpoch);
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_HISTORICAL_SUMMARY_PREV()),
            GIndex.unwrap(deployParams.gIFirstHistoricalSummary)
        );
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_HISTORICAL_SUMMARY_CURR()),
            GIndex.unwrap(deployParams.gIFirstHistoricalSummary)
        );
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_WITHDRAWAL_PREV()),
            GIndex.unwrap(deployParams.gIFirstWithdrawal)
        );
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_WITHDRAWAL_CURR()),
            GIndex.unwrap(deployParams.gIFirstWithdrawal)
        );
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_VALIDATOR_PREV()),
            GIndex.unwrap(deployParams.gIFirstValidator)
        );
        assertEq(
            GIndex.unwrap(verifier.GI_FIRST_VALIDATOR_CURR()),
            GIndex.unwrap(deployParams.gIFirstValidator)
        );
        assertEq(
            Slot.unwrap(verifier.FIRST_SUPPORTED_SLOT()),
            deployParams.verifierFirstSupportedSlot
        );
        assertEq(
            Slot.unwrap(verifier.PIVOT_SLOT()),
            deployParams.verifierFirstSupportedSlot
        );
        assertEq(
            Slot.unwrap(verifier.CAPELLA_SLOT()),
            deployParams.capellaSlot
        );
    }

    function test_roles() public view {
        assertTrue(
            verifier.hasRole(
                verifier.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            verifier.getRoleMemberCount(verifier.DEFAULT_ADMIN_ROLE()),
            adminsCount
        );

        assertTrue(verifier.hasRole(verifier.PAUSE_ROLE(), address(gateSeal)));
        assertTrue(
            verifier.hasRole(verifier.PAUSE_ROLE(), deployParams.resealManager)
        );
        assertEq(verifier.getRoleMemberCount(verifier.PAUSE_ROLE()), 2);

        assertTrue(
            verifier.hasRole(verifier.RESUME_ROLE(), deployParams.resealManager)
        );
        assertEq(verifier.getRoleMemberCount(verifier.RESUME_ROLE()), 1);
    }
}

contract ValidatorStrikesDeploymentTest is DeploymentBaseTest {
    function test_state_scratch() public view {
        assertEq(strikes.treeRoot(), bytes32(0));
        assertEq(keccak256(abi.encodePacked(strikes.treeCid())), keccak256(""));
    }

    function test_state() public view {
        assertEq(address(strikes.ejector()), address(ejector));
        assertEq(strikes.getInitializedVersion(), 1);
    }

    function test_immutables() public view {
        assertEq(address(strikesImpl.MODULE()), address(module));
        assertEq(address(strikesImpl.ACCOUNTING()), address(accounting));
        assertEq(address(strikesImpl.ORACLE()), address(oracle));
        assertEq(address(strikesImpl.EXIT_PENALTIES()), address(exitPenalties));
        assertEq(
            address(strikesImpl.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
    }

    function test_roles() public view {
        assertTrue(
            strikes.hasRole(
                strikes.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            strikes.getRoleMemberCount(strikes.DEFAULT_ADMIN_ROLE()),
            adminsCount
        );
    }

    function test_proxy() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        strikes.initialize({
            admin: deployParams.aragonAgent,
            _ejector: address(ejector)
        });

        OssifiableProxy proxy = OssifiableProxy(payable(address(strikes)));

        assertEq(proxy.proxy__getImplementation(), address(strikesImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        ValidatorStrikes strikesImpl = ValidatorStrikes(
            proxy.proxy__getImplementation()
        );
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        strikesImpl.initialize({
            admin: deployParams.aragonAgent,
            _ejector: address(ejector)
        });
    }
}

contract EjectorDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        assertFalse(ejector.isPaused());
    }

    function test_immutables() public view {
        assertEq(address(ejector.MODULE()), address(module));
        assertEq(ejector.STAKING_MODULE_ID(), deployParams.stakingModuleId);
        assertEq(address(ejector.STRIKES()), address(strikes));
    }

    function test_roles() public view {
        assertTrue(
            ejector.hasRole(
                ejector.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );
        assertEq(
            ejector.getRoleMemberCount(ejector.DEFAULT_ADMIN_ROLE()),
            adminsCount
        );
        assertTrue(ejector.hasRole(ejector.PAUSE_ROLE(), address(gateSeal)));
        assertTrue(
            ejector.hasRole(ejector.PAUSE_ROLE(), deployParams.resealManager)
        );
        assertEq(ejector.getRoleMemberCount(verifier.PAUSE_ROLE()), 2);

        assertTrue(
            ejector.hasRole(ejector.PAUSE_ROLE(), deployParams.resealManager)
        );
        assertEq(ejector.getRoleMemberCount(verifier.RESUME_ROLE()), 1);
    }
}

contract ExitPenaltiesDeploymentTest is DeploymentBaseTest {
    function test_immutables() public view {
        assertEq(address(exitPenaltiesImpl.MODULE()), address(module));
        assertEq(
            address(exitPenaltiesImpl.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
        assertEq(address(exitPenaltiesImpl.ACCOUNTING()), address(accounting));
        assertEq(address(exitPenaltiesImpl.STRIKES()), address(strikes));
    }

    function test_proxy() public view {
        OssifiableProxy proxy = OssifiableProxy(
            payable(address(exitPenalties))
        );

        assertEq(proxy.proxy__getImplementation(), address(exitPenaltiesImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());
    }
}
