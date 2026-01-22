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
import { INodeOperatorOwner } from "../interfaces/INodeOperatorOwner.sol";

import { DepositQueueLib } from "../lib/DepositQueueLib.sol";
import { SigningKeys } from "../lib/SigningKeys.sol";
import { GeneralPenalty } from "../lib/GeneralPenaltyLib.sol";
import { PausableUntil } from "../lib/utils/PausableUntil.sol";
import { WithdrawnValidatorLib } from "../lib/WithdrawnValidatorLib.sol";
import { ValidatorCountsReport } from "../lib/ValidatorCountsReport.sol";
import { NOAddresses } from "../lib/NOAddresses.sol";
import { NodeOperatorOps } from "../lib/NodeOperatorOps.sol";
import { OperatorTracker } from "../lib/OperatorTracker.sol";

import { AssetRecoverer } from "./AssetRecoverer.sol";

abstract contract ModuleLinearStorage {
    /// @dev Having this mapping here to preserve the current layout of the storage of the CSModule.
    mapping(uint256 priority => DepositQueueLib.Queue queue)
        internal _depositQueueByPriority;

    bytes32 internal __freeSlot1;
    bytes32 internal __freeSlot2;
    bytes32 internal __freeSlot3;
    bytes32 internal __freeSlot4;

    uint256 internal _nonce;
    mapping(uint256 => NodeOperator) internal _nodeOperators;
    /// @dev see _keyPointer function for details of noKeyIndexPacked structure
    mapping(uint256 noKeyIndexPacked => bool) internal _isValidatorWithdrawn;
    mapping(uint256 noKeyIndexPacked => bool) internal _isValidatorSlashed;

    uint64 internal _totalDepositedValidators;
    uint64 internal _totalExitedValidators;
    uint64 internal _depositableValidatorsCount;
    uint64 internal _nodeOperatorsCount;
}

abstract contract BaseModule is
    IBaseModule,
    ModuleLinearStorage,
    AccessControlEnumerableUpgradeable,
    PausableUntil,
    AssetRecoverer
{
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant STAKING_ROUTER_ROLE =
        keccak256("STAKING_ROUTER_ROLE");
    bytes32 public constant REPORT_GENERAL_DELAYED_PENALTY_ROLE =
        keccak256("REPORT_GENERAL_DELAYED_PENALTY_ROLE");
    bytes32 public constant SETTLE_GENERAL_DELAYED_PENALTY_ROLE =
        keccak256("SETTLE_GENERAL_DELAYED_PENALTY_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE =
        keccak256("REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE");
    bytes32 public constant REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE =
        keccak256("REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");
    bytes32 public constant CREATE_NODE_OPERATOR_ROLE =
        keccak256("CREATE_NODE_OPERATOR_ROLE");

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
        if (lidoLocator == address(0)) {
            revert ZeroLocatorAddress();
        }

        if (parametersRegistry == address(0)) {
            revert ZeroParametersRegistryAddress();
        }

        if (accounting == address(0)) {
            revert ZeroAccountingAddress();
        }

        if (exitPenalties == address(0)) {
            revert ZeroExitPenaltiesAddress();
        }

        MODULE_TYPE = moduleType;
        LIDO_LOCATOR = ILidoLocator(lidoLocator);
        STETH = IStETH(LIDO_LOCATOR.lido());
        PARAMETERS_REGISTRY = IParametersRegistry(parametersRegistry);
        ACCOUNTING = IAccounting(accounting);
        EXIT_PENALTIES = IExitPenalties(exitPenalties);
        FEE_DISTRIBUTOR = address(ACCOUNTING.FEE_DISTRIBUTOR());
    }

    /// @inheritdoc IBaseModule
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc IBaseModule
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc IBaseModule
    function createNodeOperator(
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address referrer
    )
        external
        onlyRole(CREATE_NODE_OPERATOR_ROLE)
        whenResumed
        returns (uint256 nodeOperatorId)
    {
        nodeOperatorId = _nodeOperatorsCount;
        OperatorTracker.recordCreator(nodeOperatorId);
        // solhint-disable-next-line func-named-parameters
        NodeOperatorOps.createNodeOperator(
            _nodeOperators,
            nodeOperatorId,
            from,
            managementProperties,
            referrer
        );

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

        if (
            msg.value <
            accounting.getRequiredBondForNextKeys(nodeOperatorId, keysCount)
        ) {
            revert InvalidAmount();
        }

        if (msg.value != 0) {
            accounting.depositETH{ value: msg.value }(from, nodeOperatorId);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
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

        uint256 amount = accounting.getRequiredBondForNextKeys(
            nodeOperatorId,
            keysCount
        );

        if (amount != 0) {
            accounting.depositStETH(from, nodeOperatorId, amount, permit);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
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

        uint256 amount = accounting.getRequiredBondForNextKeysWstETH(
            nodeOperatorId,
            keysCount
        );

        if (amount != 0) {
            accounting.depositWstETH(from, nodeOperatorId, amount, permit);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
    }

    /// @inheritdoc IBaseModule
    function proposeNodeOperatorManagerAddressChange(
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NOAddresses.proposeNodeOperatorManagerAddressChange(
            _nodeOperators,
            nodeOperatorId,
            proposedAddress
        );
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorManagerAddressChange(
        uint256 nodeOperatorId
    ) external {
        NOAddresses.confirmNodeOperatorManagerAddressChange(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc IBaseModule
    function proposeNodeOperatorRewardAddressChange(
        uint256 nodeOperatorId,
        address proposedAddress
    ) external {
        NOAddresses.proposeNodeOperatorRewardAddressChange(
            _nodeOperators,
            nodeOperatorId,
            proposedAddress
        );
    }

    /// @inheritdoc IBaseModule
    function confirmNodeOperatorRewardAddressChange(
        uint256 nodeOperatorId
    ) external {
        NOAddresses.confirmNodeOperatorRewardAddressChange(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc IBaseModule
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external {
        NOAddresses.resetNodeOperatorManagerAddress(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc IBaseModule
    function changeNodeOperatorRewardAddress(
        uint256 nodeOperatorId,
        address newAddress
    ) external {
        NOAddresses.changeNodeOperatorRewardAddress(
            _nodeOperators,
            nodeOperatorId,
            newAddress
        );
    }

    /// @inheritdoc IStakingModule
    /// @dev Passes through the minted stETH shares to the fee distributor
    function onRewardsMinted(
        uint256 totalShares
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        STETH.transferShares(FEE_DISTRIBUTOR, totalShares);
    }

    /// @inheritdoc IStakingModule
    function updateExitedValidatorsCount(
        bytes calldata nodeOperatorIds,
        bytes calldata exitedValidatorsCounts
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(
            nodeOperatorIds,
            exitedValidatorsCounts
        );

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (
                uint256 nodeOperatorId,
                uint256 exitedValidatorsCount
            ) = ValidatorCountsReport.next(
                    nodeOperatorIds,
                    exitedValidatorsCounts,
                    i
                );
            _updateExitedValidatorsCount({
                nodeOperatorId: nodeOperatorId,
                exitedValidatorsCount: exitedValidatorsCount,
                allowDecrease: false
            });
        }
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    function updateTargetValidatorsLimits(
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        _setTargetLimit(nodeOperatorId, targetLimitMode, targetLimit);

        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: false
        });
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    /// @dev This method is not used in the module, hence it does nothing
    /// @dev NOTE: No role checks because of empty body to save bytecode.
    function onExitedAndStuckValidatorsCountsUpdated() external {
        // solhint-disable-previous-line no-empty-blocks
        // Nothing to do, rewards are distributed by a performance oracle.
    }

    /// TODO: Figure out if we can remove the body of this function to save bytecode
    /// @inheritdoc IStakingModule
    function unsafeUpdateValidatorsCount(
        uint256 nodeOperatorId,
        uint256 exitedValidatorsKeysCount
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        _updateExitedValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            exitedValidatorsCount: exitedValidatorsKeysCount,
            allowDecrease: true
        });
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    function decreaseVettedSigningKeysCount(
        bytes calldata nodeOperatorIds,
        bytes calldata vettedSigningKeysCounts
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(
            nodeOperatorIds,
            vettedSigningKeysCounts
        );

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (
                uint256 nodeOperatorId,
                uint256 vettedSigningKeysCount
            ) = ValidatorCountsReport.next(
                    nodeOperatorIds,
                    vettedSigningKeysCounts,
                    i
                );

            _onlyExistingNodeOperator(nodeOperatorId);

            NodeOperator storage no = _nodeOperators[nodeOperatorId];

            if (vettedSigningKeysCount >= no.totalVettedKeys) {
                revert InvalidVetKeysPointer();
            }

            if (vettedSigningKeysCount < no.totalDepositedKeys) {
                revert InvalidVetKeysPointer();
            }

            // NodeOperator.totalVettedKeys and totalDepositedKeys are uint32 slots; the checks above keep
            // `vettedSigningKeysCount` within those limits, so this cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalVettedKeys = uint32(vettedSigningKeysCount);
            emit VettedSigningKeysCountChanged(
                nodeOperatorId,
                vettedSigningKeysCount
            );

            // @dev separate event for intentional decrease from Staking Router
            emit VettedSigningKeysCountDecreased(nodeOperatorId);

            // Nonce will be updated below once
            _updateDepositableValidatorsCount({
                nodeOperatorId: nodeOperatorId,
                incrementNonceIfUpdated: false
            });
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function removeKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        if (startIndex < no.totalDepositedKeys) {
            revert SigningKeysInvalidOffset();
        }

        // solhint-disable-next-line func-named-parameters
        uint256 newTotalSigningKeys = SigningKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            no.totalAddedKeys
        );

        // The Node Operator is charged for the every removed key. It's motivated by the fact that the DAO should cleanup
        // the queue from the empty batches related to the Node Operator. It's possible to have multiple batches with only one
        // key in it, so it means the DAO should be able to cover removal costs for as much batches as keys removed in this case.
        uint256 curveId = _getBondCurveId(nodeOperatorId);
        uint256 amountToCharge = PARAMETERS_REGISTRY.getKeyRemovalCharge(
            curveId
        ) * keysCount;
        bool isFullyCharged = true;

        if (amountToCharge != 0) {
            isFullyCharged = _accounting().chargeFee(
                nodeOperatorId,
                amountToCharge
            );
            emit KeyRemovalChargeApplied(nodeOperatorId);
        }

        // Added/vetted signing key counters are uint32 fields; newTotalSigningKeys is strictly
        // less than no.totalAddedKeys, so it always fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalAddedKeys = uint32(newTotalSigningKeys);
        emit TotalSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalVettedKeys = uint32(newTotalSigningKeys);
        emit VettedSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        if (!isFullyCharged) {
            _onUncompensatedPenalty(nodeOperatorId);
        }

        // Nonce is updated below due to keys state change
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: false
        });
        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external {
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc IBaseModule
    function reportGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        bytes32 penaltyType,
        uint256 amount,
        string calldata details
    ) external onlyRole(REPORT_GENERAL_DELAYED_PENALTY_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        GeneralPenalty.reportGeneralDelayedPenalty(
            nodeOperatorId,
            penaltyType,
            amount,
            details
        );
    }

    /// @inheritdoc IBaseModule
    function cancelGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyRole(REPORT_GENERAL_DELAYED_PENALTY_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        GeneralPenalty.cancelGeneralDelayedPenalty(nodeOperatorId, amount);
    }

    /// @inheritdoc IBaseModule
    function settleGeneralDelayedPenalty(
        uint256[] calldata nodeOperatorIds,
        uint256[] calldata maxAmounts
    ) external onlyRole(SETTLE_GENERAL_DELAYED_PENALTY_ROLE) {
        if (nodeOperatorIds.length != maxAmounts.length) {
            revert InvalidInput();
        }

        for (uint256 i; i < nodeOperatorIds.length; ++i) {
            uint256 nodeOperatorId = nodeOperatorIds[i];
            _onlyExistingNodeOperator(nodeOperatorId);

            bool settled = GeneralPenalty.settleGeneralDelayedPenalty(
                nodeOperatorId,
                maxAmounts[i]
            );

            if (!settled) continue;

            _onUncompensatedPenalty(nodeOperatorId);

            // Nonce should be updated if depositableValidators change
            _updateDepositableValidatorsCount({
                nodeOperatorId: nodeOperatorId,
                incrementNonceIfUpdated: true
            });
        }
    }

    /// @inheritdoc IBaseModule
    function compensateGeneralDelayedPenalty(
        uint256 nodeOperatorId
    ) external payable {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        GeneralPenalty.compensateGeneralDelayedPenalty(nodeOperatorId);
    }

    /// @inheritdoc IBaseModule
    function onValidatorSlashed(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external onlyRole(VERIFIER_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        if (keyIndex >= no.totalDepositedKeys) {
            revert SigningKeysInvalidOffset();
        }

        uint256 pointer = _keyPointer(nodeOperatorId, keyIndex);
        if (_isValidatorSlashed[pointer]) {
            revert ValidatorSlashingAlreadyReported();
        }
        _isValidatorSlashed[pointer] = true;

        bytes memory pubkey = SigningKeys.loadKeys(nodeOperatorId, keyIndex, 1);
        emit ValidatorSlashingReported(nodeOperatorId, keyIndex, pubkey);
    }

    function reportSlashedWithdrawnValidators(
        WithdrawnValidatorInfo[] calldata validatorInfos
    ) external onlyRole(REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE) {
        _reportWithdrawnValidators(validatorInfos, true);
    }

    /// @inheritdoc IBaseModule
    function reportRegularWithdrawnValidators(
        WithdrawnValidatorInfo[] calldata validatorInfos
    ) external onlyRole(REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE) {
        _reportWithdrawnValidators(validatorInfos, false);
    }

    /// @inheritdoc IStakingModule
    function reportValidatorExitDelay(
        uint256 nodeOperatorId,
        uint256,
        /* proofSlotTimestamp */
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        EXIT_PENALTIES.processExitDelayReport(
            nodeOperatorId,
            publicKey,
            eligibleToExitInSec
        );
    }

    /// @inheritdoc IStakingModule
    function onValidatorExitTriggered(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 withdrawalRequestPaidFee,
        uint256 exitType
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        EXIT_PENALTIES.processTriggeredExit(
            nodeOperatorId,
            publicKey,
            withdrawalRequestPaidFee,
            exitType
        );
    }

    /// @inheritdoc IBaseModule
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IBaseModule
    function isValidatorSlashed(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external view returns (bool) {
        return _isValidatorSlashed[_keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IBaseModule
    function isValidatorWithdrawn(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external view returns (bool) {
        return _isValidatorWithdrawn[_keyPointer(nodeOperatorId, keyIndex)];
    }

    /// @inheritdoc IStakingModule
    function getType() external view returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperator(
        uint256 nodeOperatorId
    ) external view returns (NodeOperator memory) {
        return _nodeOperators[nodeOperatorId];
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        return (
            NodeOperatorManagementProperties(
                no.managerAddress,
                no.rewardAddress,
                no.extendedManagerPermissions
            )
        );
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorOwner(
        uint256 nodeOperatorId
    ) external view returns (address) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        return
            no.extendedManagerPermissions
                ? no.managerAddress
                : no.rewardAddress;
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorNonWithdrawnKeys(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
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
        return
            NodeOperatorOps.getNodeOperatorSummary(
                _nodeOperators,
                nodeOperatorId,
                _accounting()
            );
    }

    /// @inheritdoc IBaseModule
    function getNodeOperatorTotalDepositedKeys(
        uint256 nodeOperatorId
    ) external view returns (uint256 totalDepositedKeys) {
        totalDepositedKeys = _nodeOperators[nodeOperatorId].totalDepositedKeys;
    }

    /// @inheritdoc IBaseModule
    function getSigningKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory) {
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
        // solhint-disable-next-line func-named-parameters
        SigningKeys.loadKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            keys,
            signatures,
            0
        );
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
    function getNodeOperatorIsActive(
        uint256 nodeOperatorId
    ) external view returns (bool) {
        return nodeOperatorId < _nodeOperatorsCount;
    }

    /// @inheritdoc IStakingModule
    function getNodeOperatorIds(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory nodeOperatorIds) {
        uint256 nodeOperatorsCount = _nodeOperatorsCount;
        if (offset >= nodeOperatorsCount || limit == 0) {
            return nodeOperatorIds;
        }

        unchecked {
            uint256 idsCount = nodeOperatorsCount - offset;
            if (idsCount > limit) idsCount = limit;

            nodeOperatorIds = new uint256[](idsCount);
            for (uint256 i; i < idsCount; ++i) {
                nodeOperatorIds[i] = offset++;
            }
        }
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
        return
            EXIT_PENALTIES.isValidatorExitDelayPenaltyApplicable(
                nodeOperatorId,
                publicKey,
                eligibleToExitInSec
            );
    }

    /// @inheritdoc IStakingModule
    function exitDeadlineThreshold(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        _onlyExistingNodeOperator(nodeOperatorId);
        return
            PARAMETERS_REGISTRY.getAllowedExitDelay(
                _getBondCurveId(nodeOperatorId)
            );
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable) returns (bool) {
        return
            interfaceId == type(INodeOperatorOwner).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __BaseModule_init(address admin) internal {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STAKING_ROUTER_ROLE, address(LIDO_LOCATOR.stakingRouter()));

        // Module is on pause initially and should be resumed during the vote
        _pauseFor(PausableUntil.PAUSE_INFINITELY);
    }

    function _reportWithdrawnValidators(
        WithdrawnValidatorInfo[] calldata validatorInfos,
        bool slashed
    ) internal {
        bool anySubmission;

        for (uint256 i; i < validatorInfos.length; ++i) {
            WithdrawnValidatorInfo calldata info = validatorInfos[i];
            _onlyExistingNodeOperator(info.nodeOperatorId);

            uint256 pointer = _keyPointer(info.nodeOperatorId, info.keyIndex);
            if (_isValidatorWithdrawn[pointer]) {
                continue;
            }

            if (info.isSlashed != slashed) {
                revert InvalidWithdrawnValidatorInfo();
            }

            NodeOperator storage no = _nodeOperators[info.nodeOperatorId];
            bool bondCoversPenalties = WithdrawnValidatorLib.process(
                no,
                info,
                _isValidatorSlashed[pointer]
            );
            if (!bondCoversPenalties) {
                _onUncompensatedPenalty(info.nodeOperatorId);
            }

            _updateDepositableValidatorsCount({
                nodeOperatorId: info.nodeOperatorId,
                incrementNonceIfUpdated: false
            });

            _isValidatorWithdrawn[pointer] = true;
            anySubmission = true;
        }

        if (anySubmission) {
            _incrementModuleNonce();
        }
    }

    function _incrementModuleNonce() internal {
        unchecked {
            emit NonceChanged(++_nonce);
        }
    }

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

        uint256 curveId = _getBondCurveId(nodeOperatorId);
        uint256 keysLimit = PARAMETERS_REGISTRY.getKeysLimit(curveId);

        unchecked {
            if (
                totalAddedKeys + keysCount - no.totalWithdrawnKeys > keysLimit
            ) {
                revert KeysLimitExceeded();
            }

            // solhint-disable-next-line func-named-parameters
            uint256 newTotalAddedKeys = SigningKeys.saveKeysSigs(
                nodeOperatorId,
                totalAddedKeys,
                keysCount,
                publicKeys,
                signatures
            );

            uint32 totalVettedKeys = no.totalVettedKeys;
            // Optimistic vetting takes place.
            if (totalAddedKeys == totalVettedKeys) {
                // Sum stays <= totalAddedKeys (< 2^32 by design), so the result fits uint32.
                // forge-lint: disable-next-line(unsafe-typecast)
                totalVettedKeys = totalVettedKeys + uint32(keysCount);
                no.totalVettedKeys = totalVettedKeys;
                emit VettedSigningKeysCountChanged(
                    nodeOperatorId,
                    totalVettedKeys
                );
            }

            // Added key counters are uint32 slots; hitting 2^32 keys would require unreachable bond
            // capital and calldata, so newTotalAddedKeys stays within the slot bounds.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalAddedKeys = uint32(newTotalAddedKeys);

            emit TotalSigningKeysCountChanged(
                nodeOperatorId,
                newTotalAddedKeys
            );
        }

        // Nonce is updated below since in case of target limit depositable keys might not change
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: false
        });
        _incrementModuleNonce();
    }

    function _updateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        bool incrementNonceIfUpdated
    ) internal {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        uint256 totalDepositedKeys = no.totalDepositedKeys;
        uint256 newCount = no.totalVettedKeys - totalDepositedKeys;
        uint256 unbondedKeys = _accounting().getUnbondedKeysCount(
            nodeOperatorId
        );

        uint256 nonDeposited = no.totalAddedKeys - totalDepositedKeys;
        if (unbondedKeys >= nonDeposited) {
            newCount = 0;
        } else if (unbondedKeys > no.totalAddedKeys - no.totalVettedKeys) {
            newCount = nonDeposited - unbondedKeys;
        }

        if (no.targetLimitMode > 0 && newCount > 0) {
            unchecked {
                uint256 nonWithdrawnValidators = totalDepositedKeys -
                    no.totalWithdrawnKeys;

                uint256 targetLimit = no.targetLimit;
                uint256 leftToLimit = 0;

                if (targetLimit > nonWithdrawnValidators) {
                    leftToLimit = targetLimit - nonWithdrawnValidators;
                }

                if (newCount > leftToLimit) {
                    newCount = leftToLimit;
                }
            }
        }
        _applyDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            newCount: newCount,
            incrementNonceIfUpdated: incrementNonceIfUpdated
        });
    }

    function _applyDepositableValidatorsCount(
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal virtual {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        if (no.depositableValidatorsCount == newCount) return;

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
        if (incrementNonceIfUpdated) {
            _incrementModuleNonce();
        }
    }

    /// TODO: Figure out if we can remove this method
    /// @dev Update exited validators count for a single Node Operator
    /// @dev Allows decrease the count for unsafe updates
    function _updateExitedValidatorsCount(
        uint256 nodeOperatorId,
        uint256 exitedValidatorsCount,
        bool allowDecrease
    ) internal {
        _onlyExistingNodeOperator(nodeOperatorId);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        uint32 totalExitedKeys = no.totalExitedKeys;
        if (exitedValidatorsCount == totalExitedKeys) {
            return;
        }
        if (exitedValidatorsCount > no.totalDepositedKeys) {
            revert ExitedKeysHigherThanTotalDeposited();
        }
        if (!allowDecrease && exitedValidatorsCount < totalExitedKeys) {
            revert ExitedKeysDecrease();
        }

        unchecked {
            // @dev Invariant sum(no.totalExitedKeys for no in nos) == _totalExitedValidators.
            // `_totalExitedValidators` accumulates the same uint32 per-operator counts, so pushing
            // the new value through uint64 preserves the exact result.
            // forge-lint: disable-next-item(unsafe-typecast)
            _totalExitedValidators =
                (_totalExitedValidators - totalExitedKeys) +
                uint64(exitedValidatorsCount);
        }
        // Each node operator stores its exited count in a uint32 slot; `exitedValidatorsCount`
        // is validated against `totalDepositedKeys` (also uint32), so the cast is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalExitedKeys = uint32(exitedValidatorsCount);

        emit ExitedSigningKeysCountChanged(
            nodeOperatorId,
            exitedValidatorsCount
        );
    }

    function _setTargetLimit(
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) internal {
        // solhint-disable-next-line func-named-parameters
        NodeOperatorOps.setTargetLimit(
            _nodeOperators,
            nodeOperatorId,
            targetLimitMode,
            targetLimit
        );
    }

    function _checkCanAddKeys(
        uint256 nodeOperatorId,
        address who
    ) internal view {
        // Most likely a direct call, so check the sender is a manager.
        if (who == msg.sender) {
            _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        } else {
            // We're trying to add keys via gate, check if we can do it.
            _checkRole(CREATE_NODE_OPERATOR_ROLE);
            if (OperatorTracker.getCreator(nodeOperatorId) != msg.sender) {
                revert CannotAddKeys();
            }
        }
    }

    function _onlyNodeOperatorManager(
        uint256 nodeOperatorId,
        address from
    ) internal view {
        address managerAddress = _nodeOperators[nodeOperatorId].managerAddress;
        if (managerAddress == address(0)) {
            revert NodeOperatorDoesNotExist();
        }

        if (managerAddress != from) {
            revert SenderIsNotEligible();
        }
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId < _nodeOperatorsCount) {
            return;
        }

        revert NodeOperatorDoesNotExist();
    }

    function _onlyValidIndexRange(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) internal view {
        if (
            startIndex + keysCount >
            _nodeOperators[nodeOperatorId].totalAddedKeys
        ) {
            revert SigningKeysInvalidOffset();
        }
    }

    function _getBondCurveId(
        uint256 nodeOperatorId
    ) internal view returns (uint256) {
        return _accounting().getBondCurveId(nodeOperatorId);
    }

    /// @dev This function is used to get the accounting contract from immutables to save bytecode.
    function _accounting() internal view returns (IAccounting) {
        return ACCOUNTING;
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    /// @dev Both nodeOperatorId and keyIndex are limited to uint64 by the contract
    function _keyPointer(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) internal pure returns (uint256) {
        return (nodeOperatorId << 128) | keyIndex;
    }
}
