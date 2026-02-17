// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { IStakingModule, FORCED_TARGET_LIMIT_MODE_ID } from "../interfaces/IStakingModule.sol";
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
import { OperatorTracker } from "../lib/OperatorTracker.sol";
import { KeyPointerLib } from "../lib/KeyPointerLib.sol";

import { AssetRecoverer } from "./AssetRecoverer.sol";
import { ModuleLinearStorage } from "./ModuleLinearStorage.sol";
import { PausableWithRoles } from "./PausableWithRoles.sol";

abstract contract BaseModule is
    IBaseModule,
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
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");
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
        address referrer
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _checkCreateNodeOperatorRole();
        nodeOperatorId = _nodeOperatorsCount;
        OperatorTracker.recordCreator(nodeOperatorId);
        NodeOperatorOps.createNodeOperator({
            nodeOperators: _nodeOperators,
            nodeOperatorId: nodeOperatorId,
            from: from,
            managementProperties: managementProperties,
            referrer: referrer
        });

        unchecked {
            ++_nodeOperatorsCount;
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
        NOAddresses.proposeNodeOperatorManagerAddressChange(_nodeOperators, nodeOperatorId, proposedAddress);
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorManagerAddressChange(uint256 nodeOperatorId) external {
        NOAddresses.confirmNodeOperatorManagerAddressChange(_nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function proposeNodeOperatorRewardAddressChange(uint256 nodeOperatorId, address proposedAddress) external {
        NOAddresses.proposeNodeOperatorRewardAddressChange(_nodeOperators, nodeOperatorId, proposedAddress);
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorRewardAddressChange(uint256 nodeOperatorId) external {
        NOAddresses.confirmNodeOperatorRewardAddressChange(_nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external {
        NOAddresses.resetNodeOperatorManagerAddress(_nodeOperators, nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function changeNodeOperatorRewardAddress(uint256 nodeOperatorId, address newAddress) external {
        NOAddresses.changeNodeOperatorRewardAddress(_nodeOperators, nodeOperatorId, newAddress);
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
        _totalExitedValidators = NodeOperatorOps.updateExitedValidatorsCount({
            nodeOperators: _nodeOperators,
            nodeOperatorsCount: _nodeOperatorsCount,
            totalExitedValidators: _totalExitedValidators,
            nodeOperatorIds: nodeOperatorIds,
            exitedValidatorsCounts: exitedValidatorsCounts
        });
    }

    /// @inheritdoc IStakingModule
    function updateTargetValidatorsLimits(
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) external {
        _checkStakingRouterRole();
        _setTargetLimit(nodeOperatorId, targetLimitMode, targetLimit);

        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    function decreaseVettedSigningKeysCount(
        bytes calldata nodeOperatorIds,
        bytes calldata vettedSigningKeysCounts
    ) external {
        _checkStakingRouterRole();
        NodeOperatorOps.decreaseVettedSigningKeysCount(
            _nodeOperators,
            _nodeOperatorsCount,
            nodeOperatorIds,
            vettedSigningKeysCounts
        );
    }

    /// @inheritdoc IBaseModule
    function removeKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) external virtual {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        if (startIndex < no.totalDepositedKeys) revert SigningKeysInvalidOffset();

        uint256 newTotalSigningKeys = SigningKeys.removeKeysSigs({
            nodeOperatorId: nodeOperatorId,
            startIndex: startIndex,
            keysCount: keysCount,
            totalKeysCount: no.totalAddedKeys
        });

        // Added/vetted signing key counters are uint32 fields; newTotalSigningKeys is strictly
        // less than no.totalAddedKeys, so it always fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalAddedKeys = uint32(newTotalSigningKeys);
        emit TotalSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalVettedKeys = uint32(newTotalSigningKeys);
        emit VettedSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        // Nonce is updated below due to keys state change
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
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

            // If general delayed penalty was not compensated using `compensateGeneralDelayedPenalty`,
            // we treat it the same way as when bond is not sufficient to cover the penalty.
            _onUncompensatedPenalty(nodeOperatorId);

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
    function onValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external {
        _checkVerifierRole();
        _onlyExistingNodeOperator(nodeOperatorId);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        if (keyIndex >= no.totalDepositedKeys) revert SigningKeysInvalidOffset();

        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        if (_isValidatorSlashed[pointer]) revert ValidatorSlashingAlreadyReported();
        _isValidatorSlashed[pointer] = true;

        bytes memory pubkey = SigningKeys.loadKeys(nodeOperatorId, keyIndex, 1);
        emit ValidatorSlashingReported(nodeOperatorId, keyIndex, pubkey);
    }

    /// @inheritdoc IBaseModule
    function increaseKeyAddedBalance(uint256 nodeOperatorId, uint256 keyIndex, uint256 amount) external {
        _checkVerifierRole();

        NodeOperatorOps.increaseKeyAddedBalance({
            nodeOperators: _nodeOperators,
            nodeOperatorsCount: _nodeOperatorsCount,
            isValidatorWithdrawn: _isValidatorWithdrawn,
            keyAddedBalances: _keyAddedBalances,
            nodeOperatorId: nodeOperatorId,
            keyIndex: keyIndex,
            incrementWei: amount
        });
    }

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

    /// @inheritdoc IStakingModule
    /// @dev This method is not used in the module since rewards are distributed by a performance oracle,
    ///      hence it does nothing
    // solhint-disable-next-line no-empty-blocks
    function onExitedAndStuckValidatorsCountsUpdated() external view {}

    /// @dev DEPRECATED: Should be removed in the future versions.
    /// @inheritdoc IStakingModule
    // solhint-disable-next-line no-empty-blocks
    function unsafeUpdateValidatorsCount(uint256, uint256) external view {}

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        virtual
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        totalExitedValidators = _totalExitedValidators;
        totalDepositedValidators = _totalDepositedValidators;
        depositableValidatorsCount = _depositableValidatorsCount;
    }

    /// @inheritdoc IStakingModule
    /// @dev Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
    ///      If there are depositable validators in the queue, the method should revert to prevent deposits with invalid
    ///      withdrawal credentials.
    function onWithdrawalCredentialsChanged() external view {
        _checkStakingRouterRole();
        if (_depositableValidatorsCount > 0) revert DepositableKeysWithUnsupportedWithdrawalCredentials();
    }

    /// @inheritdoc IBaseModule
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IBaseModule
    function isValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool) {
        return _isValidatorSlashed[KeyPointerLib.keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IBaseModule
    function isValidatorWithdrawn(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool) {
        return _isValidatorWithdrawn[KeyPointerLib.keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IStakingModule
    function getType() external view returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperator(uint256 nodeOperatorId) external view returns (NodeOperator memory) {
        return _nodeOperators[nodeOperatorId];
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        return (NodeOperatorManagementProperties(no.managerAddress, no.rewardAddress, no.extendedManagerPermissions));
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorOwner(uint256 nodeOperatorId) external view returns (address) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        return no.extendedManagerPermissions ? no.managerAddress : no.rewardAddress;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorNonWithdrawnKeys(uint256 nodeOperatorId) external view returns (uint256) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        unchecked {
            return no.totalAddedKeys - no.totalWithdrawnKeys;
        }
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
        return NodeOperatorOps.getNodeOperatorSummary(_nodeOperators, nodeOperatorId, _accounting());
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
        return _nonce;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorsCount() external view returns (uint256) {
        return _nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getActiveNodeOperatorsCount() external view returns (uint256) {
        return _nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorIsActive(uint256 nodeOperatorId) external view returns (bool) {
        return nodeOperatorId < _nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorIds(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory nodeOperatorIds) {
        return NodeOperatorOps.getNodeOperatorIds(_nodeOperatorsCount, offset, limit);
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
    function getKeyAddedBalance(uint256 nodeOperatorId, uint256 keyIndex) external view returns (uint256) {
        return _keyAddedBalances[KeyPointerLib.keyPointer(nodeOperatorId, keyIndex)];
    }

    // solhint-disable-next-line func-name-mixedcase
    function __BaseModule_init(address admin) internal {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STAKING_ROUTER_ROLE, address(LIDO_LOCATOR.stakingRouter()));

        // Module is on pause initially and should be resumed during the vote
        _pauseFor(PausableUntil.PAUSE_INFINITELY);
    }

    function _reportWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos, bool slashed) internal {
        bool anySubmission;

        for (uint256 i; i < validatorInfos.length; ++i) {
            WithdrawnValidatorInfo calldata info = validatorInfos[i];
            _onlyExistingNodeOperator(info.nodeOperatorId);

            uint256 pointer = KeyPointerLib.keyPointer(info.nodeOperatorId, info.keyIndex);
            if (_isValidatorWithdrawn[pointer]) continue;
            if (info.isSlashed != slashed) revert InvalidWithdrawnValidatorInfo();
            if (info.isSlashed && !_isValidatorSlashed[pointer]) revert SlashingPenaltyIsNotApplicable();

            NodeOperator storage no = _nodeOperators[info.nodeOperatorId];
            bool penaltyCovered = WithdrawnValidatorLib.process(no, info, _keyAddedBalances[pointer]);
            if (!penaltyCovered) _onUncompensatedPenalty(info.nodeOperatorId);

            _updateDepositableValidatorsCount({ nodeOperatorId: info.nodeOperatorId, incrementNonceIfUpdated: false });

            _isValidatorWithdrawn[pointer] = true;
            unchecked {
                ++_totalWithdrawnValidators;
            }
            anySubmission = true;
        }

        if (anySubmission) _incrementModuleNonce();
    }

    function _incrementModuleNonce() internal {
        unchecked {
            emit NonceChanged(++_nonce);
        }
    }

    /// @dev Prevents reactivation of a Node Operator after an uncovered penalty by
    ///      forcing its target limit to zero. Uncovered charges are not considered penalties, hence this method
    ///      is not called in such cases.
    function _onUncompensatedPenalty(uint256 nodeOperatorId) internal {
        _setTargetLimit(nodeOperatorId, FORCED_TARGET_LIMIT_MODE_ID, 0);
    }

    function _addKeysAndUpdateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) internal {
        // Do not allow of multiple calls of addValidatorKeys* methods for the creator contract.
        OperatorTracker.forgetCreator(nodeOperatorId);

        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        uint256 totalAddedKeys = no.totalAddedKeys;

        uint256 keysLimit = _parametersRegistry().getKeysLimit(_getBondCurveId(nodeOperatorId));

        unchecked {
            if (totalAddedKeys + keysCount - no.totalWithdrawnKeys > keysLimit) revert KeysLimitExceeded();

            uint256 newTotalAddedKeys = SigningKeys.saveKeysSigs({
                nodeOperatorId: nodeOperatorId,
                startIndex: totalAddedKeys,
                keysCount: keysCount,
                pubkeys: publicKeys,
                signatures: signatures
            });

            uint32 totalVettedKeys = no.totalVettedKeys;
            // Optimistic vetting takes place.
            if (totalAddedKeys == totalVettedKeys) {
                // Sum stays <= totalAddedKeys (< 2^32 by design), so the result fits uint32.
                // forge-lint: disable-next-line(unsafe-typecast)
                totalVettedKeys = totalVettedKeys + uint32(keysCount);
                no.totalVettedKeys = totalVettedKeys;
                emit VettedSigningKeysCountChanged(nodeOperatorId, totalVettedKeys);
            }

            // Added key counters are uint32 slots; hitting 2^32 keys would require unreachable bond
            // capital and calldata, so newTotalAddedKeys stays within the slot bounds.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalAddedKeys = uint32(newTotalAddedKeys);

            emit TotalSigningKeysCountChanged(nodeOperatorId, newTotalAddedKeys);
        }

        // Nonce is updated below since in case of target limit depositable keys might not change
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    function _updateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        bool incrementNonceIfUpdated
    ) internal returns (bool changed) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        uint256 totalDepositedKeys = no.totalDepositedKeys;
        uint256 newCount = no.totalVettedKeys - totalDepositedKeys;
        uint256 unbondedKeys = _accounting().getUnbondedKeysCount(nodeOperatorId);

        uint256 nonDeposited = no.totalAddedKeys - totalDepositedKeys;
        if (unbondedKeys >= nonDeposited) {
            newCount = 0;
        } else if (unbondedKeys > no.totalAddedKeys - no.totalVettedKeys) {
            newCount = nonDeposited - unbondedKeys;
        }

        if (no.targetLimitMode > 0 && newCount > 0) {
            unchecked {
                uint256 nonWithdrawnValidators = totalDepositedKeys - no.totalWithdrawnKeys;

                uint256 targetLimit = no.targetLimit;
                uint256 leftToLimit = 0;

                if (targetLimit > nonWithdrawnValidators) leftToLimit = targetLimit - nonWithdrawnValidators;
                if (newCount > leftToLimit) newCount = leftToLimit;
            }
        }
        return
            _applyDepositableValidatorsCount({
                no: no,
                nodeOperatorId: nodeOperatorId,
                newCount: newCount,
                incrementNonceIfUpdated: incrementNonceIfUpdated
            });
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
            _depositableValidatorsCount =
                _depositableValidatorsCount -
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

    function _setTargetLimit(uint256 nodeOperatorId, uint256 targetLimitMode, uint256 targetLimit) internal {
        NodeOperatorOps.setTargetLimit(_nodeOperators, nodeOperatorId, targetLimitMode, targetLimit);
    }

    function _checkCanAddKeys(uint256 nodeOperatorId, address who) internal view {
        // Most likely a direct call, so check the sender is a manager first.
        if (who == msg.sender) {
            _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        } else {
            // We're trying to add keys via gate, check if we can do it.
            _checkCreateNodeOperatorRole();
            if (OperatorTracker.getCreator(nodeOperatorId) != msg.sender) revert CannotAddKeys();
        }
    }

    function _onlyNodeOperatorManager(uint256 nodeOperatorId, address from) internal view {
        address managerAddress = _nodeOperators[nodeOperatorId].managerAddress;
        if (managerAddress == address(0)) revert NodeOperatorDoesNotExist();
        if (managerAddress != from) revert SenderIsNotEligible();
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId < _nodeOperatorsCount) return;

        revert NodeOperatorDoesNotExist();
    }

    function _onlyValidIndexRange(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) internal view {
        if (startIndex + keysCount > _nodeOperators[nodeOperatorId].totalAddedKeys) revert SigningKeysInvalidOffset();
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

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
