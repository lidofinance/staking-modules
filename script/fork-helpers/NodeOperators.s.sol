// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script } from "forge-std/Script.sol";

import { IVEBO } from "src/interfaces/IVEBO.sol";
import { IStakingRouter } from "src/interfaces/IStakingRouter.sol";
import { NodeOperator, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";

import { DeploymentFixtures } from "test/helpers/Fixtures.sol";
import { Utilities } from "test/helpers/Utilities.sol";

import { ForkHelpersCommon } from "./Common.sol";

contract NodeOperators is
    Script,
    DeploymentFixtures,
    ForkHelpersCommon,
    Utilities
{
    modifier broadcastPenaltyReporter() {
        _setUp();
        address penaltyReporter = module.getRoleMember(
            module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
            0
        );
        _setBalance(penaltyReporter);
        vm.startBroadcast(penaltyReporter);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastPenaltySettler() {
        _setUp();
        address penaltySettler = module.getRoleMember(
            module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
            0
        );
        _setBalance(penaltySettler);
        vm.startBroadcast(penaltySettler);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastVerifier() {
        _setUp();
        _setBalance(address(verifier));
        vm.startBroadcast(address(verifier));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastStakingRouter() {
        _setUp();
        _setBalance(address(stakingRouter));
        vm.startBroadcast(address(stakingRouter));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastStranger() {
        _setUp();
        address stranger = nextAddress("stranger");
        _setBalance(stranger);
        vm.startBroadcast(stranger);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastManager(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).managerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastProposedManager(uint256 noId) {
        _setUp();
        address nodeOperator = module
            .getNodeOperator(noId)
            .proposedManagerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastReward(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).managerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastProposedReward(uint256 noId) {
        _setUp();
        address nodeOperator = module
            .getNodeOperator(noId)
            .proposedRewardAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    function proposeManagerAddress(
        uint256 noId,
        address managerAddress
    ) external broadcastManager(noId) {
        module.proposeNodeOperatorManagerAddressChange(noId, managerAddress);
    }

    function proposeRewardAddress(
        uint256 noId,
        address rewardAddress
    ) external broadcastReward(noId) {
        module.proposeNodeOperatorRewardAddressChange(noId, rewardAddress);
    }

    function confirmManagerAddress(
        uint256 noId
    ) external broadcastProposedManager(noId) {
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function confirmRewardAddress(
        uint256 noId
    ) external broadcastProposedReward(noId) {
        module.confirmNodeOperatorRewardAddressChange(noId);
    }

    function addKeys(
        uint256 noId,
        uint256 keysCount
    ) external broadcastManager(noId) {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        module.addValidatorKeysETH{ value: amount }(
            msg.sender,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function deposit(uint256 depositCount) external broadcastStakingRouter {
        (, , uint256 depositableValidatorsCount) = module
            .getStakingModuleSummary();
        if (depositCount > depositableValidatorsCount) {
            depositCount = depositableValidatorsCount;
        }
        (, uint256 totalDepositedValidators, ) = module
            .getStakingModuleSummary();

        module.obtainDepositData(depositCount, "");

        (, uint256 totalDepositedValidatorsAfter, ) = module
            .getStakingModuleSummary();
        assertEq(
            totalDepositedValidatorsAfter,
            totalDepositedValidators + depositCount
        );
    }

    function removeKey(
        uint256 noId,
        uint256 keyIndex
    ) external broadcastManager(noId) {
        module.removeKeys(noId, keyIndex, 1);
    }

    function unvet(
        uint256 noId,
        uint256 vettedKeysCount
    ) external broadcastStakingRouter {
        module.decreaseVettedSigningKeysCount(
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(vettedKeysCount)
        );

        assertEq(module.getNodeOperator(noId).totalVettedKeys, vettedKeysCount);
    }

    function exit(
        uint256 noId,
        uint256 exitedKeysCount
    ) external broadcastStakingRouter {
        module.updateExitedValidatorsCount(
            _encodeNodeOperatorId(noId),
            _encodeUint128Value(exitedKeysCount)
        );

        assertEq(module.getNodeOperator(noId).totalExitedKeys, exitedKeysCount);
    }

    function slash(uint256 noId, uint256 keyIndex) external broadcastVerifier {
        module.onValidatorSlashed(noId, keyIndex);
    }

    function withdraw(
        uint256 noId,
        uint256 keyIndex,
        uint256 exitBalance,
        uint256 slashingPenalty
    ) external broadcastVerifier {
        uint256 withdrawnBefore = module
            .getNodeOperator(noId)
            .totalWithdrawnKeys;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo(
            noId,
            keyIndex,
            exitBalance,
            slashingPenalty,
            slashingPenalty > 0
        );
        module.reportWithdrawnValidators(validatorInfos);

        assertTrue(module.isValidatorWithdrawn(noId, keyIndex));
        assertEq(
            module.getNodeOperator(noId).totalWithdrawnKeys,
            withdrawnBefore + 1
        );
    }

    function targetLimit(
        uint256 noId,
        uint256 targetLimitMode,
        uint256 limit
    ) external broadcastStakingRouter {
        module.updateTargetValidatorsLimits(noId, targetLimitMode, limit);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.targetLimit, limit);
        assertEq(no.targetLimitMode, targetLimitMode);
    }

    function reportGeneralDelayedPenalty(
        uint256 noId,
        uint256 amount
    ) external broadcastPenaltyReporter {
        uint256 lockedBefore = accounting.getActualLockedBond(noId);

        module.reportGeneralDelayedPenalty(
            noId,
            bytes32(abi.encode(1)),
            amount,
            "Test penalty"
        );

        uint256 lockedAfter = accounting.getActualLockedBond(noId);
        assertEq(
            lockedAfter,
            lockedBefore +
                amount +
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(
                        accounting.getBondCurveId(noId)
                    )
        );
    }

    function cancelGeneralDelayedPenalty(
        uint256 noId,
        uint256 amount
    ) external broadcastPenaltyReporter {
        uint256 lockedBefore = accounting.getActualLockedBond(noId);

        module.cancelGeneralDelayedPenalty(noId, amount);

        uint256 lockedAfter = accounting.getActualLockedBond(noId);
        assertEq(lockedAfter, lockedBefore - amount);
    }

    function settleGeneralDelayedPenalty(
        uint256 noId
    ) external broadcastPenaltySettler {
        uint256[] memory noIds = new uint256[](1);
        noIds[0] = noId;
        uint256[] memory maxAmounts = new uint256[](1);
        maxAmounts[0] = type(uint256).max; // Set to max to settle
        module.settleGeneralDelayedPenalty(noIds, maxAmounts);

        assertEq(accounting.getActualLockedBond(noId), 0);
    }

    function compensateGeneralDelayedPenalty(
        uint256 noId,
        uint256 amount
    ) external broadcastStranger {
        uint256 lockedBefore = accounting.getActualLockedBond(noId);

        module.compensateGeneralDelayedPenalty{ value: amount }(noId);

        assertEq(accounting.getActualLockedBond(noId), lockedBefore - amount);
    }

    function exitRequest(
        uint256 noId,
        uint256 validatorIndex,
        bytes calldata validatorPubKey
    ) external {
        _setUp();
        IVEBO vebo = IVEBO(locator.validatorsExitBusOracle());
        bytes memory data;

        bytes3 moduleId = bytes3(uint24(_getModuleId()));
        // Node operator ids stay below 2^40 (queue limit), mirroring production encoding.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes5 nodeOpId = bytes5(uint40(noId));
        // Validator indices are limited by the number of keys in the queue (< 2^32), so 64 bits suffice.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes8 _validatorIndex = bytes8(uint64(validatorIndex));

        (, uint256 refSlot, , ) = vebo.getConsensusReport();
        uint256 reportRefSlot = refSlot + 1;

        data = abi.encodePacked(
            moduleId,
            nodeOpId,
            _validatorIndex,
            validatorPubKey
        );
        IVEBO.ReportData memory report = IVEBO.ReportData({
            consensusVersion: vebo.getConsensusVersion(),
            refSlot: reportRefSlot,
            requestsCount: 1,
            dataFormat: 1,
            data: data
        });

        address consensus = vebo.getConsensusContract();
        _setBalance(consensus);

        vm.startBroadcast(consensus);
        vebo.submitConsensusReport(
            keccak256(abi.encode(report)),
            reportRefSlot,
            block.timestamp + 1 days
        );
        vm.stopBroadcast();

        address veboSubmitter = _prepareVEBOSubmitter(vebo);
        vm.startBroadcast(veboSubmitter);
        vebo.submitReportData(report, vebo.getContractVersion());
        vm.stopBroadcast();
    }

    function _prepareVEBOSubmitter(
        IVEBO vebo
    ) internal returns (address veboSubmitter) {
        address veboAdmin = _prepareAdmin(address(vebo));
        veboSubmitter = nextAddress();

        vm.startBroadcast(veboAdmin);
        vebo.grantRole(vebo.SUBMIT_DATA_ROLE(), address(veboSubmitter));
        vm.stopBroadcast();

        _setBalance(address(veboSubmitter));
    }

    error NodeOperatorsModuleNotFound();

    function _getModuleId() internal view returns (uint256) {
        uint256[] memory ids = stakingRouter.getStakingModuleIds();
        for (uint256 i = ids.length - 1; i > 0; i--) {
            IStakingRouter.StakingModule memory moduleInfo = stakingRouter
                .getStakingModule(ids[i]);
            if (moduleInfo.stakingModuleAddress == address(module)) {
                return ids[i];
            }
        }
        revert NodeOperatorsModuleNotFound();
    }
}
