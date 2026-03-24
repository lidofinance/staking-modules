// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { IStakingModule, IStakingModuleV2 } from "../interfaces/IStakingModule.sol";
import { ILidoLocator } from "../interfaces/ILidoLocator.sol";
import { IStETH } from "../interfaces/IStETH.sol";
import { IParametersRegistry } from "../interfaces/IParametersRegistry.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { IExitPenalties } from "../interfaces/IExitPenalties.sol";
import { NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "../interfaces/IBaseModule.sol";
import { IBaseModule } from "../interfaces/IBaseModule.sol";

import { SigningKeys } from "../lib/SigningKeys.sol";
import { GeneralPenalty } from "../lib/GeneralPenaltyLib.sol";
import { PausableUntil } from "../lib/utils/PausableUntil.sol";
import { WithdrawnValidatorLib } from "../lib/WithdrawnValidatorLib.sol";
import { NOAddresses } from "../lib/NOAddresses.sol";
import { NodeOperatorOps } from "../lib/NodeOperatorOps.sol";
import { KeyPointerLib } from "../lib/KeyPointerLib.sol";
import { StakeTracker } from "../lib/StakeTracker.sol";

import { AssetRecoverer } from "./AssetRecoverer.sol";
import { ModuleLinearStorage } from "./ModuleLinearStorage.sol";
import { PausableWithRoles } from "./PausableWithRoles.sol";

abstract contract BaseModule is
    IBaseModule,
    IStakingModuleV2,
    ModuleLinearStorage,
    AccessControlEnumerableUpgradeable,
    PausableWithRoles,
    AssetRecoverer
{
    bytes32 public constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    bytes32 public constant REPORT_GENERAL_DELAYED_PENALTY_ROLE = keccak256("REPORT_GENERAL_DELAYED_PENALTY_ROLE");
    bytes32 public constant SETTLE_GENERAL_DELAYED_PENALTY_ROLE = keccak256("SETTLE_GENERAL_DELAYED_PENALTY_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE =
        keccak256("REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE");
    bytes32 public constant REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE =
        keccak256("REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE");
    bytes32 public constant CREATE_NODE_OPERATOR_ROLE = keccak256("CREATE_NODE_OPERATOR_ROLE");
    ILidoLocator public immutable LIDO_LOCATOR;
    IStETH public immutable STETH;
    IParametersRegistry public immutable PARAMETERS_REGISTRY;
    IAccounting public immutable ACCOUNTING;
    IExitPenalties public immutable EXIT_PENALTIES;
    address public immutable FEE_DISTRIBUTOR;

    bytes32 internal immutable MODULE_TYPE;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    ) {
        if (moduleType == bytes32(0)) revert ZeroModuleType();
        if (lidoLocator == address(0)) revert ZeroLocatorAddress();
        if (parametersRegistry == address(0)) revert ZeroParametersRegistryAddress();
        if (accounting == address(0)) revert ZeroAccountingAddress();
        if (exitPenalties == address(0)) revert ZeroExitPenaltiesAddress();

        MODULE_TYPE = moduleType;
        LIDO_LOCATOR = ILidoLocator(lidoLocator);
        STETH = IStETH(LIDO_LOCATOR.lido());
        PARAMETERS_REGISTRY = IParametersRegistry(parametersRegistry);
        ACCOUNTING = IAccounting(accounting);
        EXIT_PENALTIES = IExitPenalties(exitPenalties);
        FEE_DISTRIBUTOR = address(ACCOUNTING.FEE_DISTRIBUTOR());

        _disableInitializers();
    }

    /// @inheritdoc IBaseModule
    function createNodeOperator(
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address /* referrer */
    ) public virtual whenResumed returns (uint256 nodeOperatorId) {
        _checkCreateNodeOperatorRole();
        BaseModuleStorage storage $ = _baseStorage();
        nodeOperatorId = $.nodeOperatorsCount;

        NodeOperatorOps.createNodeOperator({
            nodeOperators: $.nodeOperators,
            nodeOperatorId: nodeOperatorId,
            from: from,
            managementProperties: managementProperties,
            stETH: address(STETH)
        });

        unchecked {
            ++$.nodeOperatorsCount;
        }

        // If all operators have up-to-date deposit info, then the new operator also has it, so we can just increase the counter.
        if (nodeOperatorId == $.upToDateOperatorDepositInfoCount) {
            ++$.upToDateOperatorDepositInfoCount;
        }
        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function addValidatorKeysETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) external payable whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        IAccounting accounting = _accounting();

        if (msg.value < _getRequiredBondForNextKeys(accounting, nodeOperatorId, keysCount)) revert InvalidAmount();
        if (msg.value != 0) accounting.depositETH{ value: msg.value }(from, nodeOperatorId);

        _addKeysAndUpdateDepositableValidatorsCount(nodeOperatorId, keysCount, publicKeys, signatures);
    }

    /// @inheritdoc IBaseModule
    function addValidatorKeysStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        IAccounting.PermitInput calldata permit
    ) external whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        IAccounting accounting = _accounting();

        uint256 amount = _getRequiredBondForNextKeys(accounting, nodeOperatorId, keysCount);
        if (amount != 0) accounting.depositStETH(from, nodeOperatorId, amount, permit);

        _addKeysAndUpdateDepositableValidatorsCount(nodeOperatorId, keysCount, publicKeys, signatures);
    }

    /// @inheritdoc IBaseModule
    function addValidatorKeysWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        IAccounting.PermitInput calldata permit
    ) external whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        IAccounting accounting = _accounting();

        uint256 amount = accounting.getRequiredBondForNextKeysWstETH(nodeOperatorId, keysCount);
        if (amount != 0) accounting.depositWstETH(from, nodeOperatorId, amount, permit);

        _addKeysAndUpdateDepositableValidatorsCount(nodeOperatorId, keysCount, publicKeys, signatures);
    }

    /// @inheritdoc IBaseModule
    function proposeNodeOperatorManagerAddressChange(uint256 nodeOperatorId, address proposedAddress) external {
        NOAddresses.proposeNodeOperatorManagerAddressChange(
            _baseStorage().nodeOperators,
            nodeOperatorId,
            proposedAddress
        );
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorManagerAddressChange(uint256 nodeOperatorId) external {
        NOAddresses.confirmNodeOperatorManagerAddressChange(_baseStorage().nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function proposeNodeOperatorRewardAddressChange(uint256 nodeOperatorId, address proposedAddress) external {
        NOAddresses.proposeNodeOperatorRewardAddressChange(
            _baseStorage().nodeOperators,
            nodeOperatorId,
            proposedAddress
        );
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorRewardAddressChange(uint256 nodeOperatorId) external {
        NOAddresses.confirmNodeOperatorRewardAddressChange(_baseStorage().nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external {
        NOAddresses.resetNodeOperatorManagerAddress(_baseStorage().nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function changeNodeOperatorRewardAddress(uint256 nodeOperatorId, address newAddress) external {
        NOAddresses.changeNodeOperatorRewardAddress(
            _baseStorage().nodeOperators,
            nodeOperatorId,
            newAddress,
            address(STETH)
        );
    }

    /// @inheritdoc IStakingModule
    /// @dev Passes through the minted stETH shares to the fee distributor
    function onRewardsMinted(uint256 totalShares) external {
        _checkStakingRouterRole();
        STETH.transferShares(FEE_DISTRIBUTOR, totalShares);
    }

    /// @dev DEPRECATED: Should be removed in the future versions.
    /// @inheritdoc IStakingModule
    function updateExitedValidatorsCount(
        bytes calldata nodeOperatorIds,
        bytes calldata exitedValidatorsCounts
    ) external {
        _checkStakingRouterRole();
        NodeOperatorOps.updateExitedValidatorsCount(_baseStorage(), nodeOperatorIds, exitedValidatorsCounts);
    }

    /// @dev DEPRECATED: Should be removed in the future versions.
    /// @inheritdoc IStakingModule
    function unsafeUpdateValidatorsCount(uint256 nodeOperatorId, uint256 exitedValidatorsCount) external {
        _checkStakingRouterRole();
        NodeOperatorOps.unsafeUpdateValidatorsCount(_baseStorage(), nodeOperatorId, exitedValidatorsCount);
    }

    /// @inheritdoc IStakingModule
    function updateTargetValidatorsLimits(
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) external {
        _checkStakingRouterRole();

        NodeOperatorOps.setTargetLimit(_baseStorage().nodeOperators, nodeOperatorId, targetLimitMode, targetLimit);

        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    function decreaseVettedSigningKeysCount(
        bytes calldata nodeOperatorIds,
        bytes calldata vettedSigningKeysCounts
    ) external {
        _checkStakingRouterRole();
        NodeOperatorOps.decreaseVettedSigningKeysCount(_baseStorage(), nodeOperatorIds, vettedSigningKeysCounts);
    }

    /// @inheritdoc IBaseModule
    function removeKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) external virtual {
        _removeKeys(nodeOperatorId, startIndex, keysCount, false);
    }

    /// @inheritdoc IBaseModule
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external {
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: true });
    }

    /// @inheritdoc IBaseModule
    function reportGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        bytes32 penaltyType,
        uint256 amount,
        string calldata details
    ) external {
        _checkReportGeneralDelayedPenaltyRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        GeneralPenalty.reportGeneralDelayedPenalty(nodeOperatorId, penaltyType, amount, details);
    }

    /// @inheritdoc IBaseModule
    function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount) external {
        _checkReportGeneralDelayedPenaltyRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        GeneralPenalty.cancelGeneralDelayedPenalty(nodeOperatorId, amount);
    }

    /// @inheritdoc IBaseModule
    function settleGeneralDelayedPenalty(uint256[] calldata nodeOperatorIds, uint256[] calldata maxAmounts) external {
        _checkRole(SETTLE_GENERAL_DELAYED_PENALTY_ROLE);
        if (nodeOperatorIds.length != maxAmounts.length) revert InvalidInput();

        for (uint256 i; i < nodeOperatorIds.length; ++i) {
            uint256 nodeOperatorId = nodeOperatorIds[i];
            _onlyExistingNodeOperator(nodeOperatorId);

            bool settled = GeneralPenalty.settleGeneralDelayedPenalty(nodeOperatorId, maxAmounts[i]);

            if (!settled) continue;

            // Nonce should be updated if depositableValidators change
            _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: true });
        }
    }

    /// @inheritdoc IBaseModule
    function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        GeneralPenalty.compensateGeneralDelayedPenalty(nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function reportValidatorSlashing(uint256 nodeOperatorId, uint256 keyIndex) external {
        _checkVerifierRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        BaseModuleStorage storage $ = _baseStorage();
        NodeOperator storage no = $.nodeOperators[nodeOperatorId];
        if (keyIndex >= no.totalDepositedKeys) revert SigningKeysInvalidOffset();

        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        if ($.isValidatorSlashed[pointer]) revert ValidatorSlashingAlreadyReported();
        $.isValidatorSlashed[pointer] = true;

        bytes memory pubkey = SigningKeys.loadKeys(nodeOperatorId, keyIndex, 1);
        emit ValidatorSlashingReported(nodeOperatorId, keyIndex, pubkey);
    }

    /// @inheritdoc IBaseModule
    function reportValidatorBalance(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 currentBalanceWei
    ) public virtual {
        _checkVerifierRole();

        NodeOperatorOps.reportValidatorBalance({
            $: _baseStorage(),
            nodeOperatorId: nodeOperatorId,
            keyIndex: keyIndex,
            currentBalanceWei: currentBalanceWei
        });

        // NOTE: We do not increment nonce because individual validator balances don't change the distribution
        // returned by the module. The distribution from `allocateDeposits` might change but still meets
        // expectations of StakingRouter.
    }

    /// @inheritdoc IBaseModule
    function reportSlashedWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external {
        _checkRole(REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE);
        _reportWithdrawnValidators(validatorInfos, true);
    }

    /// @inheritdoc IBaseModule
    function reportRegularWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external {
        _checkRole(REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE);
        _reportWithdrawnValidators(validatorInfos, false);
    }

    /// @inheritdoc IStakingModule
    function reportValidatorExitDelay(
        uint256 nodeOperatorId,
        uint256,
        /* proofSlotTimestamp */
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external {
        _checkStakingRouterRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        _exitPenalties().processExitDelayReport(nodeOperatorId, publicKey, eligibleToExitInSec);
    }

    /// @inheritdoc IStakingModule
    function onValidatorExitTriggered(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 elWithdrawalRequestFeePaid,
        uint256 exitType
    ) external {
        _checkStakingRouterRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        _exitPenalties().processTriggeredExit(nodeOperatorId, publicKey, elWithdrawalRequestFeePaid, exitType);
    }

    /// @inheritdoc IBaseModule
    function updateDepositInfo(uint256 nodeOperatorId) external {
        _updateDepositInfo(nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function requestFullDepositInfoUpdate() external {
        _canRequestDepositInfoUpdate();
        _baseStorage().upToDateOperatorDepositInfoCount = 0;
        emit FullDepositInfoUpdateRequested();
        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function batchDepositInfoUpdate(uint256 maxCount) external returns (uint256 operatorsLeft) {
        if (maxCount == 0) revert InvalidInput();

        BaseModuleStorage storage $ = _baseStorage();
        uint256 operatorsCount = $.nodeOperatorsCount;
        uint256 noId = $.upToDateOperatorDepositInfoCount;
        if (noId == operatorsCount) return 0;

        uint256 limit = noId + maxCount > operatorsCount ? operatorsCount : noId + maxCount;

        for (; noId < limit; ++noId) {
            _updateDepositInfo(noId);
        }

        $.upToDateOperatorDepositInfoCount = limit;
        operatorsLeft = operatorsCount - limit;

        if (operatorsLeft == 0) emit NodeOperatorDepositInfoFullyUpdated();
    }

    /// @inheritdoc IStakingModule
    /// @dev This method is not used in the module since rewards are distributed by a performance oracle,
    ///      hence it does nothing
    // solhint-disable-next-line no-empty-blocks
    function onExitedAndStuckValidatorsCountsUpdated() external view {}

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        virtual
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        BaseModuleStorage storage $ = _baseStorage();
        totalExitedValidators = $.totalExitedValidators;
        totalDepositedValidators = $.totalDepositedValidators;
        depositableValidatorsCount = $.depositableValidatorsCount;
    }

    /// @inheritdoc IStakingModule
    /// @dev Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
    ///      If there are depositable validators in the queue, the method should revert to prevent deposits with invalid
    ///      withdrawal credentials.
    function onWithdrawalCredentialsChanged() external view {
        _checkStakingRouterRole();
        if (_baseStorage().depositableValidatorsCount > 0) revert DepositableKeysWithUnsupportedWithdrawalCredentials();
    }

    /// @inheritdoc IBaseModule
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IBaseModule
    function isValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool) {
        return _baseStorage().isValidatorSlashed[KeyPointerLib.keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IBaseModule
    function isValidatorWithdrawn(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool) {
        return _baseStorage().isValidatorWithdrawn[KeyPointerLib.keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IStakingModule
    function getType() external view returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperator(uint256 nodeOperatorId) external view returns (NodeOperator memory) {
        return _baseStorage().nodeOperators[nodeOperatorId];
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory) {
        NodeOperator storage no = _baseStorage().nodeOperators[nodeOperatorId];
        return (NodeOperatorManagementProperties(no.managerAddress, no.rewardAddress, no.extendedManagerPermissions));
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorOwner(uint256 nodeOperatorId) external view returns (address) {
        NodeOperator storage no = _baseStorage().nodeOperators[nodeOperatorId];
        return no.extendedManagerPermissions ? no.managerAddress : no.rewardAddress;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorNonWithdrawnKeys(uint256 nodeOperatorId) external view returns (uint256) {
        NodeOperator storage no = _baseStorage().nodeOperators[nodeOperatorId];
        unchecked {
            return no.totalAddedKeys - no.totalWithdrawnKeys;
        }
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorBalance(uint256 nodeOperatorId) external view returns (uint256) {
        return StakeTracker.getOperatorBalance(_baseStorage(), nodeOperatorId);
    }

    /// @inheritdoc IStakingModule
    /// @notice depositableValidatorsCount depends on:
    ///      - totalVettedKeys
    ///      - totalDepositedKeys
    ///      - totalExitedKeys
    ///      - targetLimitMode
    ///      - targetValidatorsCount
    ///      - totalUnbondedKeys
    function getNodeOperatorSummary(
        uint256 nodeOperatorId
    )
        external
        view
        returns (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {
        return NodeOperatorOps.getNodeOperatorSummary(_baseStorage().nodeOperators, nodeOperatorId, _accounting());
    }

    /// @inheritdoc IBaseModule
    function getSigningKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory keys) {
        _onlyValidIndexRange(nodeOperatorId, startIndex, keysCount);

        return SigningKeys.loadKeys(nodeOperatorId, startIndex, keysCount);
    }

    /// @inheritdoc IBaseModule
    function getSigningKeysWithSignatures(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory keys, bytes memory signatures) {
        _onlyValidIndexRange(nodeOperatorId, startIndex, keysCount);

        (keys, signatures) = SigningKeys.initKeysSigsBuf(keysCount);
        SigningKeys.loadKeysSigs({
            nodeOperatorId: nodeOperatorId,
            startIndex: startIndex,
            keysCount: keysCount,
            pubkeys: keys,
            signatures: signatures,
            bufOffset: 0
        });
    }

    /// @inheritdoc IStakingModule
    function getNonce() external view returns (uint256) {
        return _baseStorage().nonce;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorsCount() external view returns (uint256) {
        return _baseStorage().nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getActiveNodeOperatorsCount() external view returns (uint256) {
        return _baseStorage().nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorIsActive(uint256 nodeOperatorId) external view returns (bool) {
        return nodeOperatorId < _baseStorage().nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorIds(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory nodeOperatorIds) {
        return NodeOperatorOps.getNodeOperatorIds(_baseStorage().nodeOperatorsCount, offset, limit);
    }

    /// @inheritdoc IStakingModule
    function isValidatorExitDelayPenaltyApplicable(
        uint256 nodeOperatorId,
        uint256,
        /* proofSlotTimestamp */
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external view returns (bool) {
        _onlyExistingNodeOperator(nodeOperatorId);
        return _exitPenalties().isValidatorExitDelayPenaltyApplicable(nodeOperatorId, publicKey, eligibleToExitInSec);
    }

    /// @inheritdoc IStakingModule
    function exitDeadlineThreshold(uint256 nodeOperatorId) external view returns (uint256) {
        _onlyExistingNodeOperator(nodeOperatorId);
        return _parametersRegistry().getAllowedExitDelay(_getBondCurveId(nodeOperatorId));
    }

    /// @inheritdoc IBaseModule
    function getKeyAllocatedBalances(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances) {
        _onlyValidIndexRange(nodeOperatorId, startIndex, keysCount);
        return NodeOperatorOps.getKeyAllocatedBalances(_baseStorage(), nodeOperatorId, startIndex, keysCount);
    }

    /// @inheritdoc IBaseModule
    function getKeyConfirmedBalances(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances) {
        _onlyValidIndexRange(nodeOperatorId, startIndex, keysCount);
        return NodeOperatorOps.getKeyConfirmedBalances(_baseStorage(), nodeOperatorId, startIndex, keysCount);
    }

    function getTotalModuleStake() public view override returns (uint256) {
        return StakeTracker.getTotalModuleStake(_baseStorage());
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorDepositInfoToUpdateCount() external view returns (uint256 count) {
        BaseModuleStorage storage $ = _baseStorage();
        count = $.nodeOperatorsCount - $.upToDateOperatorDepositInfoCount;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __BaseModule_init(address admin) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STAKING_ROUTER_ROLE, address(LIDO_LOCATOR.stakingRouter()));

        // Module is on pause initially and should be resumed during the vote
        _pauseFor(PausableUntil.PAUSE_INFINITELY);
    }

    function _updateDepositInfo(uint256 nodeOperatorId) internal virtual {
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: true });
    }

    function _reportWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos, bool slashed) internal {
        (
            uint256[] memory touchedOperatorIds,
            uint256[] memory trackedBalanceDecreases,
            uint256 touchedCount
        ) = WithdrawnValidatorLib.processBatch(validatorInfos, slashed, _baseStorage());

        if (touchedCount == 0) return;

        unchecked {
            _baseStorage().totalWithdrawnValidators += touchedCount;
        }
        for (uint256 i; i < touchedCount; ++i) {
            StakeTracker.decreaseOperatorBalance(_baseStorage(), touchedOperatorIds[i], trackedBalanceDecreases[i]);
            _updateDepositableValidatorsCount({
                nodeOperatorId: touchedOperatorIds[i],
                incrementNonceIfUpdated: false
            });
        }

        _incrementModuleNonce();
    }

    function _incrementModuleNonce() internal {
        unchecked {
            emit NonceChanged(++_baseStorage().nonce);
        }
    }

    function _addKeysAndUpdateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) internal virtual {
        NodeOperatorOps.addKeys({
            nodeOperators: _baseStorage().nodeOperators,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures
        });

        // Nonce is updated below since in case of target limit depositable keys might not change
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    function _updateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        bool incrementNonceIfUpdated
    ) internal returns (bool changed) {
        return
            _applyDepositableValidatorsCount({
                no: _baseStorage().nodeOperators[nodeOperatorId],
                nodeOperatorId: nodeOperatorId,
                newCount: NodeOperatorOps.calculateDepositableValidatorsCount(
                    _baseStorage().nodeOperators,
                    nodeOperatorId
                ),
                incrementNonceIfUpdated: incrementNonceIfUpdated
            });
    }

    function _removeKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount,
        bool useKeyRemovalCharge
    ) internal virtual {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        NodeOperatorOps.removeKeys({
            nodeOperators: _baseStorage().nodeOperators,
            nodeOperatorId: nodeOperatorId,
            startIndex: startIndex,
            keysCount: keysCount,
            useKeyRemovalCharge: useKeyRemovalCharge
        });
        // Nonce is updated below due to keys state change
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal virtual returns (bool changed) {
        if (no.depositableValidatorsCount == newCount) return false;

        // Updating the global counter.
        unchecked {
            _baseStorage().depositableValidatorsCount =
                _baseStorage().depositableValidatorsCount -
                no.depositableValidatorsCount +
                // Each term is bounded by uint32 counts, so fitting into uint64 is safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint64(newCount);
        }
        // NodeOperator.depositableValidatorsCount is uint32, and newCount is derived from the same bounds.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.depositableValidatorsCount = uint32(newCount);
        emit DepositableSigningKeysCountChanged(nodeOperatorId, newCount);
        if (incrementNonceIfUpdated) _incrementModuleNonce();

        return true;
    }

    function _checkCanAddKeys(uint256 nodeOperatorId, address who) internal view virtual {
        if (who != msg.sender) {
            revert CannotAddKeys();
        }
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
    }

    function _onlyNodeOperatorManager(uint256 nodeOperatorId, address from) internal view {
        address managerAddress = _baseStorage().nodeOperators[nodeOperatorId].managerAddress;
        if (managerAddress == address(0)) revert NodeOperatorDoesNotExist();
        if (managerAddress != from) revert SenderIsNotEligible();
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId < _baseStorage().nodeOperatorsCount) return;

        revert NodeOperatorDoesNotExist();
    }

    function _onlyValidIndexRange(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) internal view {
        if (startIndex + keysCount > _baseStorage().nodeOperators[nodeOperatorId].totalAddedKeys)
            revert SigningKeysInvalidOffset();
    }

    function _getBondCurveId(uint256 nodeOperatorId) internal view returns (uint256) {
        return _accounting().getBondCurveId(nodeOperatorId);
    }

    function _getRequiredBondForNextKeys(
        IAccounting accounting,
        uint256 nodeOperatorId,
        uint256 keysCount
    ) internal view returns (uint256 amount) {
        amount = accounting.getRequiredBondForNextKeys(nodeOperatorId, keysCount);
    }

    function _checkStakingRouterRole() internal view {
        _checkRole(STAKING_ROUTER_ROLE);
    }

    function _checkReportGeneralDelayedPenaltyRole() internal view {
        _checkRole(REPORT_GENERAL_DELAYED_PENALTY_ROLE);
    }

    function _checkVerifierRole() internal view {
        _checkRole(VERIFIER_ROLE);
    }

    function _checkCreateNodeOperatorRole() internal view {
        _checkRole(CREATE_NODE_OPERATOR_ROLE);
    }

    /// @dev This function is used to get the accounting contract from immutables to save bytecode.
    function _accounting() internal view returns (IAccounting) {
        return ACCOUNTING;
    }

    /// @dev This function is used to get the exit penalties contract from immutables to save bytecode.
    function _exitPenalties() internal view returns (IExitPenalties) {
        return EXIT_PENALTIES;
    }

    /// @dev This function is used to get the parameters registry contract from immutables to save bytecode.
    function _parametersRegistry() internal view returns (IParametersRegistry) {
        return PARAMETERS_REGISTRY;
    }

    function _requireDepositInfoUpToDate() internal view {
        BaseModuleStorage storage $ = _baseStorage();
        if ($.upToDateOperatorDepositInfoCount != $.nodeOperatorsCount) revert DepositInfoIsNotUpToDate();
    }

    /// @dev Default implementation of the guard for requesting deposit info update.
    function _canRequestDepositInfoUpdate() internal view virtual {
        if (msg.sender != address(_accounting())) {
            revert SenderIsNotEligible();
        }
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
