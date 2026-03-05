// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Bytes } from "@openzeppelin/contracts/utils/Bytes.sol";

import { TwoPhaseFrameConfigUpdate } from "src/utils/TwoPhaseFrameConfigUpdate.sol";
import { IFeeOracle } from "src/interfaces/IFeeOracle.sol";

import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { Utilities } from "../../helpers/Utilities.sol";

contract TwoPhaseFrameConfigUpdateTest is Test, Utilities, DeploymentFixtures {
    TwoPhaseFrameConfigUpdate public updater;

    uint256 constant EPOCHS_PER_DAY = 225;

    uint256 internal reportsToProcessBeforeOffsetPhase;
    uint256 internal reportsToProcessBeforeRestorePhase;
    uint256 internal offsetPhaseEpochsPerFrame;
    uint256 internal restorePhaseFastLaneLengthSlots;

    function dayToEpochs(uint256 dayCount) internal pure returns (uint256) {
        return dayCount * EPOCHS_PER_DAY;
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        if (!_isEmpty(env.UTILS_DEPLOY_CONFIG)) {
            string memory utilsConfig = vm.readFile(env.UTILS_DEPLOY_CONFIG);
            address deployed = vm.parseJsonAddress(utilsConfig, ".TwoPhaseFrameConfigUpdate");
            assertTrue(deployed.code.length > 0, "TwoPhaseFrameConfigUpdate not deployed on fork");

            bytes memory encodedParams = vm.parseJsonBytes(utilsConfig, ".TwoPhaseFrameConfigUpdateParams");
            (
                reportsToProcessBeforeOffsetPhase,
                reportsToProcessBeforeRestorePhase,
                offsetPhaseEpochsPerFrame,
                restorePhaseFastLaneLengthSlots
            ) = abi.decode(encodedParams, (uint256, uint256, uint256, uint256));

            updater = TwoPhaseFrameConfigUpdate(deployed);
            assertEq(address(updater.ORACLE()), address(oracle), "Utility oracle mismatch");
        } else {
            reportsToProcessBeforeOffsetPhase = 1;
            reportsToProcessBeforeRestorePhase = 1;
            offsetPhaseEpochsPerFrame = dayToEpochs(31);
            restorePhaseFastLaneLengthSlots = 300;

            _ensureOracleIsAtCurrentFrame();

            TwoPhaseFrameConfigUpdate.PhasesConfig memory phasesConfig = TwoPhaseFrameConfigUpdate.PhasesConfig({
                reportsToProcessBeforeOffsetPhase: reportsToProcessBeforeOffsetPhase,
                reportsToProcessBeforeRestorePhase: reportsToProcessBeforeRestorePhase,
                offsetPhaseEpochsPerFrame: offsetPhaseEpochsPerFrame,
                restorePhaseFastLaneLengthSlots: restorePhaseFastLaneLengthSlots
            });

            updater = new TwoPhaseFrameConfigUpdate(address(oracle), phasesConfig);
        }

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        bytes32 adminRole = hashConsensus.getRoleAdmin(manageFrameRole);
        address admin = hashConsensus.getRoleMember(adminRole, 0);
        vm.prank(admin);
        hashConsensus.grantRole(manageFrameRole, address(updater));
    }

    function _ensureOracleIsAtCurrentFrame() internal {
        uint256 lastProcessingRefSlot = oracle.getLastProcessingRefSlot();
        (uint256 currentRefSlot, ) = hashConsensus.getCurrentFrame();
        if (currentRefSlot == lastProcessingRefSlot) return;

        uint256 consensusVersion = oracle.getConsensusVersion();
        uint256 contractVersion = oracle.getContractVersion();

        IFeeOracle.ReportData memory report = IFeeOracle.ReportData({
            consensusVersion: consensusVersion,
            refSlot: currentRefSlot,
            treeRoot: someBytes32(),
            treeCid: someCIDv0(),
            logCid: someCIDv0(),
            distributed: 0,
            rebate: 0,
            strikesTreeRoot: someBytes32(),
            strikesTreeCid: someCIDv0()
        });
        bytes32 reportHash = keccak256(abi.encode(report));

        (address[] memory members, ) = hashConsensus.getFastLaneMembers();
        for (uint256 i; i < members.length; i++) {
            vm.prank(members[i]);
            hashConsensus.submitReport(currentRefSlot, reportHash, consensusVersion);
        }

        bytes32 submitRole = oracle.SUBMIT_DATA_ROLE();
        bytes32 adminRole = oracle.getRoleAdmin(submitRole);
        address admin = oracle.getRoleMember(adminRole, 0);
        vm.prank(admin);
        oracle.grantRole(submitRole, address(this));
        oracle.submitReportData(report, contractVersion);
        oracle.renounceRole(submitRole, address(this));
    }

    function test_deployParams() public {
        Env memory env = envVars();
        vm.skip(_isEmpty(env.UTILS_DEPLOY_CONFIG), "UTILS_DEPLOY_CONFIG is not set");

        string memory utilsConfig = vm.readFile(env.UTILS_DEPLOY_CONFIG);
        bytes memory encodedParams = vm.parseJsonBytes(utilsConfig, ".TwoPhaseFrameConfigUpdateParams");
        (
            uint256 reportsToProcessBeforeOffsetPhaseFromConfig,
            uint256 reportsToProcessBeforeRestorePhaseFromConfig,
            uint256 offsetPhaseEpochsPerFrameFromConfig,
            uint256 restorePhaseFastLaneLengthSlotsFromConfig
        ) = abi.decode(encodedParams, (uint256, uint256, uint256, uint256));

        {
            uint256 slotsPerEpoch = updater.SLOTS_PER_EPOCH();

            (
                uint256 offsetExpectedProcessingRefSlot,
                ,
                uint256 offsetPhaseEpochsPerFrameActual,
                uint256 offsetFastLaneLengthSlotsActual,

            ) = updater.offsetPhase();

            (uint256 restoreExpectedProcessingRefSlot, , , uint256 restoreFastLaneLengthSlotsActual, ) = updater
                .restorePhase();

            assertEq(
                offsetPhaseEpochsPerFrameActual,
                offsetPhaseEpochsPerFrameFromConfig,
                "Offset phase epochsPerFrame mismatch"
            );
            assertEq(offsetFastLaneLengthSlotsActual, 0, "Offset phase fast lane should be disabled");
            assertEq(
                restoreFastLaneLengthSlotsActual,
                restorePhaseFastLaneLengthSlotsFromConfig,
                "Restore phase fast lane length mismatch"
            );
            assertEq(
                restoreExpectedProcessingRefSlot - offsetExpectedProcessingRefSlot,
                reportsToProcessBeforeRestorePhaseFromConfig * offsetPhaseEpochsPerFrameFromConfig * slotsPerEpoch,
                "Restore phase expected ref slot mismatch"
            );
        }

        // Check reportsToProcessBeforeOffsetPhase by deployment time
        {
            uint256 deployBlockNumber = _utilsDeployBlockNumber(env.UTILS_DEPLOY_CONFIG);
            vm.createSelectFork(env.RPC_URL, deployBlockNumber);

            uint256 lastProcessingRefSlotAtDeployTime = oracle.getLastProcessingRefSlot();
            (uint256 currentRefSlotAtDeployTime, ) = hashConsensus.getCurrentFrame();
            assertEq(
                currentRefSlotAtDeployTime,
                lastProcessingRefSlotAtDeployTime,
                "Sanity: report main phase not completed at deploy time"
            );

            (, uint256 currentEpochsPerFrameAtDeployTime, ) = hashConsensus.getFrameConfig();
            (uint256 slotsPerEpochAtDeployTime, , ) = hashConsensus.getChainConfig();

            (uint256 offsetExpectedProcessingRefSlot, , , , ) = updater.offsetPhase();
            assertEq(
                offsetExpectedProcessingRefSlot,
                lastProcessingRefSlotAtDeployTime +
                    (reportsToProcessBeforeOffsetPhaseFromConfig *
                        currentEpochsPerFrameAtDeployTime *
                        slotsPerEpochAtDeployTime),
                "Offset phase expected ref slot mismatch"
            );
        }
    }

    function _utilsDeployBlockNumber(string memory utilsDeployConfigPath) internal returns (uint256 deployBlockNumber) {
        string memory transactionsPath = string.concat(_dirOf(utilsDeployConfigPath), "transactions.json");
        vm.skip(!vm.exists(transactionsPath), "transactions.json does not exist near UTILS_DEPLOY_CONFIG");

        string memory transactionsJson = vm.readFile(transactionsPath);
        string memory deployBlockNumberHex = vm.parseJsonString(transactionsJson, ".receipts[0].blockNumber");
        deployBlockNumber = vm.parseUint(deployBlockNumberHex);
    }

    function _dirOf(string memory path) internal pure returns (string memory dir) {
        bytes memory b = bytes(path);
        if (b.length == 0) return "";

        uint256 i = Bytes.lastIndexOf(b, "/");
        if (i == type(uint256).max) return "";
        dir = string(Bytes.slice(b, 0, i + 1));
    }

    function test_shiftReportWindow() public {
        uint256 genesisTime = updater.GENESIS_TIME();
        uint256 secondsPerSlot = updater.SECONDS_PER_SLOT();
        uint256 slotsPerEpoch = updater.SLOTS_PER_EPOCH();

        (, uint256 currentEpochsPerFrame, ) = hashConsensus.getFrameConfig();

        uint256 offsetExpectedProcessingRefSlot;
        uint256 offsetEpochsPerFrameFromState;
        uint256 restoreExpectedProcessingRefSlot;

        {
            (
                uint256 expectedRefSlot,
                uint256 expirationSlot,
                uint256 epochsPerFrame,
                uint256 fastLaneSlots,
                bool executed
            ) = updater.offsetPhase();
            assertFalse(executed, "Offset phase should not be executed");
            assertEq(epochsPerFrame, offsetPhaseEpochsPerFrame, "Offset phase epochs per frame mismatch");
            assertEq(fastLaneSlots, 0, "Offset phase fast lane should be disabled");

            uint256 minEpochsPerFrame = epochsPerFrame < currentEpochsPerFrame ? epochsPerFrame : currentEpochsPerFrame;
            assertEq(
                expirationSlot,
                expectedRefSlot + (minEpochsPerFrame * slotsPerEpoch),
                "Offset phase expiration should match formula"
            );

            offsetExpectedProcessingRefSlot = expectedRefSlot;
            offsetEpochsPerFrameFromState = epochsPerFrame;
        }

        {
            (
                uint256 expectedRefSlot,
                uint256 expirationSlot,
                uint256 epochsPerFrame,
                uint256 fastLaneSlots,
                bool executed
            ) = updater.restorePhase();
            assertFalse(executed, "Restore phase should not be executed");
            assertEq(epochsPerFrame, currentEpochsPerFrame, "Restore phase should keep current frame length");
            assertEq(fastLaneSlots, restorePhaseFastLaneLengthSlots, "Restore phase fast lane length mismatch");

            uint256 minEpochsPerFrame = offsetEpochsPerFrameFromState < epochsPerFrame
                ? offsetEpochsPerFrameFromState
                : epochsPerFrame;
            assertEq(
                expirationSlot,
                expectedRefSlot + (minEpochsPerFrame * slotsPerEpoch),
                "Restore phase expiration should match formula"
            );

            restoreExpectedProcessingRefSlot = expectedRefSlot;
        }

        {
            uint256 expectedRestoreExpectedProcessingRefSlot = offsetExpectedProcessingRefSlot +
                (reportsToProcessBeforeRestorePhase * offsetEpochsPerFrameFromState * slotsPerEpoch);
            assertEq(
                restoreExpectedProcessingRefSlot,
                expectedRestoreExpectedProcessingRefSlot,
                "Restore phase expected slot should match config"
            );
        }

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(offsetExpectedProcessingRefSlot) // Simulate report processed for offset phase
        );

        // Warp time to align with offset phase scenario (one frame after deployment)
        {
            uint256 warpTime = genesisTime + (offsetExpectedProcessingRefSlot + 47) * secondsPerSlot; // +47 = random offset within frame
            vm.warp(warpTime);
        }

        assertTrue(updater.isReadyForOffsetPhase(), "Should be ready for offset phase");
        assertFalse(updater.isReadyForRestorePhase(), "Should not be ready for restore phase yet");

        updater.executeOffsetPhase();

        // Verify offset frame configuration changes
        {
            (
                uint256 offsetPhaseInitialEpoch,
                uint256 offsetPhaseEpochsPerFrameActual,
                uint256 offsetPhaseFastLaneSlotsActual
            ) = hashConsensus.getFrameConfig();
            assertEq(
                offsetPhaseInitialEpoch,
                (offsetExpectedProcessingRefSlot + 1) / slotsPerEpoch,
                "Initial epoch should change to current frame ref slot epoch"
            );
            assertEq(
                offsetPhaseEpochsPerFrameActual,
                offsetEpochsPerFrameFromState,
                "Offset phase should set configured frame length"
            );
            assertEq(offsetPhaseFastLaneSlotsActual, 0, "Fast lane slots should be 0 on offset phase");
        }

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(restoreExpectedProcessingRefSlot) // Simulate report processed for RestorePhase
        );

        // Warp time to align with one frame processing after offset execution
        {
            uint256 calculatedOffsetFirstFrameRefSlot = offsetExpectedProcessingRefSlot +
                (offsetEpochsPerFrameFromState * slotsPerEpoch);

            uint256 warpTime = genesisTime + (calculatedOffsetFirstFrameRefSlot + 34) * secondsPerSlot; // +34 = random offset within frame
            vm.warp(warpTime);

            (uint256 offsetFirstFrameRefSlot, ) = hashConsensus.getCurrentFrame();
            assertEq(
                offsetFirstFrameRefSlot,
                calculatedOffsetFirstFrameRefSlot,
                "Offset phase frame should progress correctly"
            );
        }

        vm.warp(genesisTime + (restoreExpectedProcessingRefSlot + 34) * secondsPerSlot);
        (uint256 restoreFrameRefSlot, ) = hashConsensus.getCurrentFrame();
        assertEq(
            restoreFrameRefSlot,
            restoreExpectedProcessingRefSlot,
            "Restore phase frame should progress correctly"
        );

        assertTrue(updater.isReadyForRestorePhase(), "Should be ready for restore phase");

        updater.executeRestorePhase();

        // Verify Restore phase frame configuration changes
        {
            (
                uint256 restorePhaseInitialEpoch,
                uint256 restorePhaseEpochsPerFrameActual,
                uint256 restorePhaseFastLaneSlotsActual
            ) = hashConsensus.getFrameConfig();
            assertEq(
                restorePhaseInitialEpoch,
                (restoreExpectedProcessingRefSlot + 1) / slotsPerEpoch,
                "Initial epoch should change to restore expected slot epoch"
            );
            assertEq(
                restorePhaseEpochsPerFrameActual,
                currentEpochsPerFrame,
                "Restore phase should restore original frame length"
            );
            assertEq(
                restorePhaseFastLaneSlotsActual,
                restorePhaseFastLaneLengthSlots,
                "Fast lane slots should remain configured value"
            );
        }

        {
            (, , , , bool offsetPhaseExecutedFlag) = updater.offsetPhase();
            (, , , , bool restorePhaseExecutedFlag) = updater.restorePhase();

            assertTrue(offsetPhaseExecutedFlag, "Offset phase should be executed");
            assertTrue(restorePhaseExecutedFlag, "Restore phase should be executed");
        }

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced after restore phase"
        );
    }

    function test_renounceRoleWhenOffsetPhaseExpired() public {
        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        uint256 genesisTime = updater.GENESIS_TIME();
        uint256 secondsPerSlot = updater.SECONDS_PER_SLOT();

        (, uint256 offsetPhaseExpirationSlot, , , ) = updater.offsetPhase();

        // Warp past offset phase expiration without executing any phases
        vm.warp(genesisTime + (offsetPhaseExpirationSlot + 1) * secondsPerSlot);

        updater.renounceRoleWhenExpired();

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced when offset phase expired"
        );
    }

    function test_renounceRoleWhenRestorePhaseExpiredAfterOffsetPhase() public {
        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        uint256 genesisTime = updater.GENESIS_TIME();
        uint256 secondsPerSlot = updater.SECONDS_PER_SLOT();

        (uint256 offsetExpectedProcessingRefSlot, , , , ) = updater.offsetPhase();

        // Mock oracle ref slot to allow offset phase execution
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(offsetExpectedProcessingRefSlot)
        );

        // Warp into the offset phase frame window
        vm.warp(genesisTime + (offsetExpectedProcessingRefSlot + 1) * secondsPerSlot);

        updater.executeOffsetPhase();

        (, uint256 restorePhaseExpirationSlot, , , ) = updater.restorePhase();

        // Warp past restore phase expiration without executing it
        vm.warp(genesisTime + (restorePhaseExpirationSlot + 1) * secondsPerSlot);

        updater.renounceRoleWhenExpired();

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced when restore phase expired after offset phase execution"
        );
    }
}
