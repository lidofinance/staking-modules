// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { StdCheats } from "forge-std/StdCheats.sol";
import { LidoMock } from "./mocks/LidoMock.sol";
import { WstETHMock } from "./mocks/WstETHMock.sol";
import { LidoLocatorMock } from "./mocks/LidoLocatorMock.sol";
import { BurnerMock } from "./mocks/BurnerMock.sol";
import { WithdrawalQueueMock } from "./mocks/WithdrawalQueueMock.sol";
import { Stub } from "./mocks/Stub.sol";
import "forge-std/Test.sol";
import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ILido } from "../../src/interfaces/ILido.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";
import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IGateSeal } from "../../src/interfaces/IGateSeal.sol";
import { NodeOperator, NodeOperatorManagementProperties } from "../../src/interfaces/ICSModule.sol";
import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { IWithdrawalQueue } from "../../src/interfaces/IWithdrawalQueue.sol";
import { CSModule } from "../../src/CSModule.sol";
import { CSParametersRegistry } from "../../src/CSParametersRegistry.sol";
import { PermissionlessGate } from "../../src/PermissionlessGate.sol";
import { VettedGate } from "../../src/VettedGate.sol";
import { VettedGateFactory } from "../../src/VettedGateFactory.sol";
import { CSAccounting } from "../../src/CSAccounting.sol";
import { CSFeeOracle } from "../../src/CSFeeOracle.sol";
import { CSFeeDistributor } from "../../src/CSFeeDistributor.sol";
import { CSEjector } from "../../src/CSEjector.sol";
import { CSExitPenalties } from "../../src/CSExitPenalties.sol";
import { CSStrikes } from "../../src/CSStrikes.sol";
import { CSVerifier } from "../../src/CSVerifier.sol";
import { DeployParams } from "../../script/DeployBase.s.sol";
import { IACL } from "../../src/interfaces/IACL.sol";
import { IKernel } from "../../src/interfaces/IKernel.sol";
import { Utilities } from "./Utilities.sol";
import { Batch } from "../../src/lib/QueueLib.sol";
import { TWGMock } from "./mocks/TWGMock.sol";

contract Fixtures is StdCheats, Test {
    bytes32 public constant INITIALIZABLE_STORAGE =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    function initLido()
        public
        returns (
            LidoLocatorMock locator,
            WstETHMock wstETH,
            LidoMock stETH,
            BurnerMock burner,
            WithdrawalQueueMock wq
        )
    {
        stETH = new LidoMock({ _totalPooledEther: 8013386371917025835991984 });
        stETH.mintShares({
            _account: address(stETH),
            _sharesAmount: 7059313073779349112833523
        });
        burner = new BurnerMock(address(stETH));
        Stub elVault = new Stub();
        wstETH = new WstETHMock(address(stETH));
        wq = new WithdrawalQueueMock(address(wstETH), address(stETH));
        Stub treasury = new Stub();
        Stub stakingRouter = new Stub();
        TWGMock twg = new TWGMock();
        locator = new LidoLocatorMock(
            address(stETH),
            address(burner),
            address(wq),
            address(elVault),
            address(treasury),
            address(stakingRouter),
            address(twg)
        );
        vm.label(address(stETH), "lido");
        vm.label(address(wstETH), "wstETH");
        vm.label(address(locator), "locator");
        vm.label(address(burner), "burner");
        vm.label(address(wq), "wq");
        vm.label(address(elVault), "elVault");
        vm.label(address(treasury), "treasury");
        vm.label(address(stakingRouter), "stakingRouter");
        vm.label(address(twg), "triggerableWithdrawalsGateway");
    }

    function _enableInitializers(address implementation) internal {
        // cheat to allow implementation initialisation
        vm.store(implementation, INITIALIZABLE_STORAGE, bytes32(0));
    }
}

contract DeploymentHelpers is Test {
    struct Env {
        string RPC_URL;
        string DEPLOY_CONFIG;
        uint256 VOTE_PREV_BLOCK;
    }

    struct DeploymentConfig {
        uint256 chainId;
        address csm;
        address csmImpl;
        address permissionlessGate;
        address vettedGateFactory;
        address vettedGate;
        address vettedGateImpl;
        address parametersRegistry;
        address parametersRegistryImpl;
        /// legacy from v1
        address earlyAdoption;
        address accounting;
        address accountingImpl;
        address oracle;
        address oracleImpl;
        address feeDistributor;
        address feeDistributorImpl;
        address ejector;
        address exitPenalties;
        address exitPenaltiesImpl;
        address strikes;
        address strikesImpl;
        address verifier;
        address verifierV2;
        address hashConsensus;
        address lidoLocator;
        address gateSeal;
        address gateSealV2;
    }

    function envVars() public returns (Env memory) {
        Env memory env = Env(
            vm.envOr("RPC_URL", string("")),
            vm.envOr("DEPLOY_CONFIG", string("")),
            vm.envOr("VOTE_PREV_BLOCK", uint256(0))
        );
        vm.skip(_isEmpty(env.RPC_URL));
        vm.skip(_isEmpty(env.DEPLOY_CONFIG));
        return env;
    }

    function parseDeploymentConfig(
        string memory config
    ) public returns (DeploymentConfig memory deploymentConfig) {
        deploymentConfig.chainId = vm.parseJsonUint(config, ".ChainId");

        deploymentConfig.csm = vm.parseJsonAddress(config, ".CSModule");
        vm.label(deploymentConfig.csm, "csm");

        deploymentConfig.csmImpl = vm.parseJsonAddress(config, ".CSModuleImpl");
        vm.label(deploymentConfig.csmImpl, "csmImpl");

        /// Optional for v1 compatibility (upgrade tests). Removed in v2
        if (vm.keyExistsJson(config, ".CSEarlyAdoption")) {
            deploymentConfig.earlyAdoption = vm.parseJsonAddress(
                config,
                ".CSEarlyAdoption"
            );
            vm.label(deploymentConfig.earlyAdoption, "earlyAdoption");
        }

        /// Optional, new in v2. Gates and other stuff not present in v1 deployment configs
        if (vm.keyExistsJson(config, ".PermissionlessGate")) {
            deploymentConfig.permissionlessGate = vm.parseJsonAddress(
                config,
                ".PermissionlessGate"
            );
            vm.label(deploymentConfig.permissionlessGate, "permissionlessGate");

            deploymentConfig.vettedGateFactory = vm.parseJsonAddress(
                config,
                ".VettedGateFactory"
            );
            vm.label(deploymentConfig.vettedGateFactory, "vettedGateFactory");

            deploymentConfig.vettedGate = vm.parseJsonAddress(
                config,
                ".VettedGate"
            );
            vm.label(deploymentConfig.vettedGate, "vettedGate");

            deploymentConfig.vettedGateImpl = vm.parseJsonAddress(
                config,
                ".VettedGateImpl"
            );
            vm.label(deploymentConfig.vettedGateImpl, "vettedGateImpl");

            deploymentConfig.parametersRegistry = vm.parseJsonAddress(
                config,
                ".CSParametersRegistry"
            );
            vm.label(deploymentConfig.parametersRegistry, "parametersRegistry");

            deploymentConfig.parametersRegistryImpl = vm.parseJsonAddress(
                config,
                ".CSParametersRegistryImpl"
            );
            vm.label(
                deploymentConfig.parametersRegistryImpl,
                "parametersRegistryImpl"
            );

            deploymentConfig.exitPenalties = vm.parseJsonAddress(
                config,
                ".CSExitPenalties"
            );
            vm.label(deploymentConfig.exitPenalties, "exitPenalties");

            deploymentConfig.exitPenaltiesImpl = vm.parseJsonAddress(
                config,
                ".CSExitPenaltiesImpl"
            );
            vm.label(deploymentConfig.exitPenaltiesImpl, "exitPenaltiesImpl");

            deploymentConfig.strikes = vm.parseJsonAddress(
                config,
                ".CSStrikes"
            );
            vm.label(deploymentConfig.strikes, "strikes");

            deploymentConfig.strikesImpl = vm.parseJsonAddress(
                config,
                ".CSStrikesImpl"
            );
            vm.label(deploymentConfig.strikesImpl, "strikesImpl");

            deploymentConfig.ejector = vm.parseJsonAddress(
                config,
                ".CSEjector"
            );
            vm.label(deploymentConfig.strikes, "ejector");
        }

        deploymentConfig.accounting = vm.parseJsonAddress(
            config,
            ".CSAccounting"
        );
        vm.label(deploymentConfig.accounting, "accounting");

        deploymentConfig.accountingImpl = vm.parseJsonAddress(
            config,
            ".CSAccountingImpl"
        );
        vm.label(deploymentConfig.accounting, "accountingImpl");

        deploymentConfig.oracle = vm.parseJsonAddress(config, ".CSFeeOracle");
        vm.label(deploymentConfig.oracle, "oracle");

        deploymentConfig.oracleImpl = vm.parseJsonAddress(
            config,
            ".CSFeeOracleImpl"
        );
        vm.label(deploymentConfig.oracleImpl, "oracleImpl");

        deploymentConfig.feeDistributor = vm.parseJsonAddress(
            config,
            ".CSFeeDistributor"
        );
        vm.label(deploymentConfig.feeDistributor, "feeDistributor");

        deploymentConfig.feeDistributorImpl = vm.parseJsonAddress(
            config,
            ".CSFeeDistributorImpl"
        );
        vm.label(deploymentConfig.feeDistributorImpl, "feeDistributorImpl");

        deploymentConfig.verifier = vm.parseJsonAddress(config, ".CSVerifier");
        if (vm.keyExistsJson(config, ".CSVerifierV2")) {
            deploymentConfig.verifierV2 = vm.parseJsonAddress(
                config,
                ".CSVerifierV2"
            );
            vm.label(deploymentConfig.verifierV2, "verifierV2");
        }
        vm.label(deploymentConfig.verifier, "verifier");

        deploymentConfig.hashConsensus = vm.parseJsonAddress(
            config,
            ".HashConsensus"
        );
        vm.label(deploymentConfig.hashConsensus, "hashConsensus");

        deploymentConfig.lidoLocator = vm.parseJsonAddress(
            config,
            ".LidoLocator"
        );
        vm.label(deploymentConfig.lidoLocator, "LidoLocator");

        deploymentConfig.gateSeal = vm.parseJsonAddress(config, ".GateSeal");
        if (vm.keyExistsJson(config, ".GateSealV2")) {
            deploymentConfig.gateSealV2 = vm.parseJsonAddress(
                config,
                ".GateSealV2"
            );
            vm.label(deploymentConfig.gateSealV2, "GateSealV2");
        }
        vm.label(deploymentConfig.gateSeal, "GateSeal");
    }

    function parseDeployParams(
        string memory deployConfigPath
    ) internal view returns (DeployParams memory) {
        string memory config = vm.readFile(deployConfigPath);
        return
            abi.decode(
                vm.parseJsonBytes(config, ".DeployParams"),
                (DeployParams)
            );
    }

    function _isEmpty(string memory s) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(s)) == keccak256(abi.encodePacked(""));
    }
}

contract DeploymentFixtures is StdCheats, DeploymentHelpers {
    CSModule public csm;
    CSModule public csmImpl;
    CSParametersRegistry public parametersRegistry;
    CSParametersRegistry public parametersRegistryImpl;
    PermissionlessGate public permissionlessGate;
    VettedGateFactory public vettedGateFactory;
    VettedGate public vettedGate;
    VettedGate public vettedGateImpl;
    address public earlyAdoption;
    CSAccounting public accounting;
    CSAccounting public accountingImpl;
    CSFeeOracle public oracle;
    CSFeeOracle public oracleImpl;
    CSFeeDistributor public feeDistributor;
    CSFeeDistributor public feeDistributorImpl;
    CSExitPenalties public exitPenalties;
    CSExitPenalties public exitPenaltiesImpl;
    CSStrikes public strikes;
    CSStrikes public strikesImpl;
    CSEjector public ejector;
    CSVerifier public verifier;
    HashConsensus public hashConsensus;
    ILidoLocator public locator;
    IWstETH public wstETH;
    IStakingRouter public stakingRouter;
    ILido public lido;
    IGateSeal public gateSeal;
    IBurner public burner;

    error CSModuleNotFound();

    function initializeFromDeployment() public {
        Env memory env = envVars();
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        DeploymentConfig memory deploymentConfig = parseDeploymentConfig(
            config
        );
        assertEq(deploymentConfig.chainId, block.chainid, "ChainId mismatch");

        csm = CSModule(deploymentConfig.csm);
        csmImpl = CSModule(deploymentConfig.csmImpl);
        parametersRegistry = CSParametersRegistry(
            deploymentConfig.parametersRegistry
        );
        parametersRegistryImpl = CSParametersRegistry(
            deploymentConfig.parametersRegistryImpl
        );
        permissionlessGate = PermissionlessGate(
            deploymentConfig.permissionlessGate
        );
        vettedGateFactory = VettedGateFactory(
            deploymentConfig.vettedGateFactory
        );
        vettedGate = VettedGate(deploymentConfig.vettedGate);
        vettedGateImpl = VettedGate(deploymentConfig.vettedGateImpl);
        earlyAdoption = deploymentConfig.earlyAdoption;
        accounting = CSAccounting(deploymentConfig.accounting);
        accountingImpl = CSAccounting(deploymentConfig.accountingImpl);
        oracle = CSFeeOracle(deploymentConfig.oracle);
        oracleImpl = CSFeeOracle(deploymentConfig.oracleImpl);
        feeDistributor = CSFeeDistributor(deploymentConfig.feeDistributor);
        feeDistributorImpl = CSFeeDistributor(
            deploymentConfig.feeDistributorImpl
        );
        ejector = CSEjector(payable(deploymentConfig.ejector));
        exitPenalties = CSExitPenalties(deploymentConfig.exitPenalties);
        exitPenaltiesImpl = CSExitPenalties(deploymentConfig.exitPenaltiesImpl);
        strikes = CSStrikes(deploymentConfig.strikes);
        strikesImpl = CSStrikes(deploymentConfig.strikesImpl);
        verifier = CSVerifier(
            deploymentConfig.verifierV2 == address(0)
                ? deploymentConfig.verifier
                : deploymentConfig.verifierV2
        );
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        locator = ILidoLocator(deploymentConfig.lidoLocator);
        lido = ILido(locator.lido());
        stakingRouter = IStakingRouter(locator.stakingRouter());
        wstETH = IWstETH(IWithdrawalQueue(locator.withdrawalQueue()).WSTETH());
        gateSeal = IGateSeal(
            deploymentConfig.gateSealV2 == address(0)
                ? deploymentConfig.gateSeal
                : deploymentConfig.gateSealV2
        );
        burner = IBurner(locator.burner());
    }

    function handleStakingLimit() public {
        address agent = stakingRouter.getRoleMember(
            stakingRouter.DEFAULT_ADMIN_ROLE(),
            0
        );
        IACL acl = IACL(IKernel(lido.kernel()).acl());
        bytes32 role = lido.STAKING_CONTROL_ROLE();
        vm.prank(acl.getPermissionManager(address(lido), role));
        acl.grantPermission(agent, address(lido), role);

        vm.prank(agent);
        lido.removeStakingLimit();
    }

    function handleBunkerMode() public {
        IWithdrawalQueue wq = IWithdrawalQueue(locator.withdrawalQueue());
        if (wq.isBunkerModeActive()) {
            vm.prank(wq.getRoleMember(wq.ORACLE_ROLE(), 0));
            wq.onOracleReport(false, 0, 0);
        }
    }

    function hugeDeposit() internal {
        // It's impossible to process deposits if withdrawal requests amount is more than the buffered ether,
        // so we need to make sure that the buffered ether is enough by submitting this tremendous amount.
        handleStakingLimit();
        handleBunkerMode();

        address whale = address(100499);
        vm.prank(whale);
        vm.deal(whale, 1e7 ether);
        lido.submit{ value: 1e7 ether }(address(0));
    }

    function findCSModule() internal view returns (uint256) {
        uint256[] memory ids = stakingRouter.getStakingModuleIds();
        for (uint256 i = ids.length - 1; i > 0; i--) {
            IStakingRouter.StakingModule memory module = stakingRouter
                .getStakingModule(ids[i]);
            if (module.stakingModuleAddress == address(csm)) {
                return ids[i];
            }
        }
        revert CSModuleNotFound();
    }

    function addNodeOperator(
        address from,
        uint256 keysCount
    ) internal returns (uint256 nodeOperatorId) {
        (bytes memory keys, bytes memory signatures) = new Utilities()
            .keysSignatures(keysCount);
        uint256 amount = accounting.getBondAmountByKeysCount(keysCount, 0);
        vm.deal(from, amount);

        vm.prank(from);
        nodeOperatorId = permissionlessGate.addNodeOperatorETH{
            value: amount
        }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
    }

    function getDepositableNodeOperator(
        address nodeOperatorAddress
    ) internal returns (uint256 noId, uint256 keysCount) {
        csm.cleanDepositQueue({ maxItems: 2 * csm.getNonce() });
        for (uint256 i = 0; i <= csm.QUEUE_LOWEST_PRIORITY(); ++i) {
            (uint128 head, ) = csm.depositQueuePointers(i);
            Batch batch = csm.depositQueueItem(i, head);
            if (!batch.isNil()) {
                return (batch.noId(), batch.keys());
            }
        }
        keysCount = 5;
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
    }

    function getDepositedNodeOperator(
        address nodeOperatorAddress,
        uint256 keysCount
    ) internal returns (uint256 noId) {
        uint256 nosCount = csm.getNodeOperatorsCount();
        for (; noId < nosCount; ++noId) {
            NodeOperator memory no = csm.getNodeOperator(noId);
            if (no.totalDepositedKeys - no.totalWithdrawnKeys >= keysCount) {
                return noId;
            }
        }
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
        (, , uint256 depositableValidatorsCount) = csm
            .getStakingModuleSummary();
        vm.startPrank(address(stakingRouter));
        // potentially time-consuming or reverting due to block/tx gas limit
        csm.obtainDepositData(depositableValidatorsCount, "");
        vm.stopPrank();
    }

    function getDepositedNodeOperatorWithSequentialActiveKeys(
        address nodeOperatorAddress,
        uint256 keysCount
    ) internal returns (uint256 noId, uint256 startIndex) {
        uint256 nosCount = csm.getNodeOperatorsCount();
        for (; noId < nosCount; ++noId) {
            NodeOperator memory no = csm.getNodeOperator(noId);
            uint256 activeKeys = no.totalDepositedKeys - no.totalWithdrawnKeys;
            if (activeKeys >= keysCount) {
                uint256 sequentialKeys = 0;
                for (uint256 i = 0; i < no.totalDepositedKeys; ++i) {
                    if (!csm.isValidatorWithdrawn(noId, i)) {
                        sequentialKeys++;
                    } else {
                        sequentialKeys = 0;
                    }
                    if (sequentialKeys == keysCount) {
                        return (noId, i - (keysCount - 1));
                    }
                }
            }
        }
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
        (, , uint256 depositableValidatorsCount) = csm
            .getStakingModuleSummary();
        vm.startPrank(address(stakingRouter));
        // potentially time-consuming or reverting due to block/tx gas limit
        csm.obtainDepositData(depositableValidatorsCount, "");
        vm.stopPrank();
        return (noId, 0);
    }
}
