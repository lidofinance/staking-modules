// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { ILidoLocator } from "./interfaces/ILidoLocator.sol";
import { IStETH } from "./interfaces/IStETH.sol";
import { ICSParametersRegistry } from "./interfaces/ICSParametersRegistry.sol";
import { ICSAccounting } from "./interfaces/ICSAccounting.sol";
import { ICSExitPenalties } from "./interfaces/ICSExitPenalties.sol";
import { ICSModule, NodeOperator, NodeOperatorManagementProperties, ValidatorWithdrawalInfo } from "./interfaces/ICSModule.sol";
import { ExitPenaltyInfo } from "./interfaces/ICSExitPenalties.sol";

import { PausableUntil } from "./lib/utils/PausableUntil.sol";
import { QueueLib, Batch } from "./lib/QueueLib.sol";
import { ValidatorCountsReport } from "./lib/ValidatorCountsReport.sol";
import { NOAddresses } from "./lib/NOAddresses.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";

contract CSModule is
    ICSModule,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUntil,
    AssetRecoverer
{
    using QueueLib for QueueLib.Queue;

    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant STAKING_ROUTER_ROLE =
        keccak256("STAKING_ROUTER_ROLE");
    bytes32 public constant REPORT_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("REPORT_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 public constant SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");
    bytes32 public constant CREATE_NODE_OPERATOR_ROLE =
        keccak256("CREATE_NODE_OPERATOR_ROLE");

    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;
    uint256 public constant PENALTY_QUOTIENT = 32 ether;
    uint256 public constant MAX_PENALTY_MULTIPLIER = 64;

    // @dev see IStakingModule.sol
    uint8 private constant FORCED_TARGET_LIMIT_MODE_ID = 2;
    // keccak256(abi.encode(uint256(keccak256("OPERATORS_CREATED_IN_TX_MAP_TSLOT")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OPERATORS_CREATED_IN_TX_MAP_TSLOT =
        0x1b07bc0838fdc4254cbabb5dd0c94d936f872c6758547168d513d8ad1dc3a500;

    bytes32 private immutable MODULE_TYPE;
    ILidoLocator public immutable LIDO_LOCATOR;
    IStETH public immutable STETH;
    ICSParametersRegistry public immutable PARAMETERS_REGISTRY;
    ICSAccounting public immutable ACCOUNTING;
    ICSExitPenalties public immutable EXIT_PENALTIES;
    address public immutable FEE_DISTRIBUTOR;

    /// @dev QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].
    uint256 public immutable QUEUE_LOWEST_PRIORITY;
    /// @dev QUEUE_LEGACY_PRIORITY is the priority for the CSM v1 queue.
    uint256 public immutable QUEUE_LEGACY_PRIORITY;

    ////////////////////////
    // State variables below
    ////////////////////////

    /// @custom:oz-renamed-from keyRemovalCharge
    /// @custom:oz-retyped-from uint256
    mapping(uint256 queuePriority => QueueLib.Queue queue)
        internal _queueByPriority;

    /// @dev Legacy queue (priority=QUEUE_LEGACY_PRIORITY), that should be removed in the future once there are no more batches in it.
    /// @custom:oz-renamed-from depositQueue
    QueueLib.Queue internal _legacyQueue;

    /// @dev Unused. Nullified in the finalizeUpgradeV2
    /// @custom:oz-renamed-from accounting
    ICSAccounting internal _accountingOld;

    /// @dev Unused. Nullified in the finalizeUpgradeV2
    /// @custom:oz-renamed-from earlyAdoption
    address internal _earlyAdoption;
    /// @dev deprecated. Nullified in the finalizeUpgradeV2
    /// @custom:oz-renamed-from publicRelease
    bool internal _publicRelease;

    uint256 private _nonce;
    mapping(uint256 => NodeOperator) internal _nodeOperators;
    /// @dev see _keyPointer function for details of noKeyIndexPacked structure
    mapping(uint256 noKeyIndexPacked => bool) private _isValidatorWithdrawn;
    /// @dev DEPRECATED! No writes expected after CSM v2
    mapping(uint256 noKeyIndexPacked => bool) private _isValidatorSlashed;

    uint64 private _totalDepositedValidators;
    uint64 private _totalExitedValidators;
    uint64 private _depositableValidatorsCount;
    uint64 private _nodeOperatorsCount;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address _accounting,
        address exitPenalties
    ) {
        if (lidoLocator == address(0)) {
            revert ZeroLocatorAddress();
        }

        if (parametersRegistry == address(0)) {
            revert ZeroParametersRegistryAddress();
        }

        if (_accounting == address(0)) {
            revert ZeroAccountingAddress();
        }

        if (exitPenalties == address(0)) {
            revert ZeroExitPenaltiesAddress();
        }

        MODULE_TYPE = moduleType;
        LIDO_LOCATOR = ILidoLocator(lidoLocator);
        STETH = IStETH(LIDO_LOCATOR.lido());
        PARAMETERS_REGISTRY = ICSParametersRegistry(parametersRegistry);
        QUEUE_LOWEST_PRIORITY = PARAMETERS_REGISTRY.QUEUE_LOWEST_PRIORITY();
        QUEUE_LEGACY_PRIORITY = PARAMETERS_REGISTRY.QUEUE_LEGACY_PRIORITY();
        ACCOUNTING = ICSAccounting(_accounting);
        EXIT_PENALTIES = ICSExitPenalties(exitPenalties);
        FEE_DISTRIBUTOR = address(ACCOUNTING.feeDistributor());

        _disableInitializers();
    }

    /// @notice initialize the module from scratch
    function initialize(address admin) external reinitializer(2) {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STAKING_ROUTER_ROLE, address(LIDO_LOCATOR.stakingRouter()));

        // CSM is on pause initially and should be resumed during the vote
        _pauseFor(PausableUntil.PAUSE_INFINITELY);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 1 to version 2 for the existing version 1 deployment.
    ///      If the version 2 contract is deployed from scratch, the `initialize` method should be used instead.
    function finalizeUpgradeV2() external reinitializer(2) {
        assembly ("memory-safe") {
            sstore(_queueByPriority.slot, 0x00)
            sstore(_earlyAdoption.slot, 0x00)
            sstore(_accountingOld.slot, 0x00)
        }
    }

    /// @inheritdoc ICSModule
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc ICSModule
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc ICSModule
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
        if (from == address(0)) {
            revert ZeroSenderAddress();
        }

        nodeOperatorId = _nodeOperatorsCount;
        _recordOperatorCreator(nodeOperatorId);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        address managerAddress = managementProperties.managerAddress ==
            address(0)
            ? from
            : managementProperties.managerAddress;
        address rewardAddress = managementProperties.rewardAddress == address(0)
            ? from
            : managementProperties.rewardAddress;
        no.managerAddress = managerAddress;
        no.rewardAddress = rewardAddress;
        if (managementProperties.extendedManagerPermissions) {
            no.extendedManagerPermissions = true;
        }

        unchecked {
            ++_nodeOperatorsCount;
        }

        emit NodeOperatorAdded(
            nodeOperatorId,
            managerAddress,
            rewardAddress,
            managementProperties.extendedManagerPermissions
        );

        if (referrer != address(0)) {
            emit ReferrerSet(nodeOperatorId, referrer);
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function addValidatorKeysETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) external payable whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        ICSAccounting _accounting = accounting();

        if (
            msg.value <
            _accounting.getRequiredBondForNextKeys(nodeOperatorId, keysCount)
        ) {
            revert InvalidAmount();
        }

        if (msg.value != 0) {
            _accounting.depositETH{ value: msg.value }(from, nodeOperatorId);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
    }

    /// @inheritdoc ICSModule
    function addValidatorKeysStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        ICSAccounting.PermitInput calldata permit
    ) external whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        ICSAccounting _accounting = accounting();

        uint256 amount = _accounting.getRequiredBondForNextKeys(
            nodeOperatorId,
            keysCount
        );

        if (amount != 0) {
            _accounting.depositStETH(from, nodeOperatorId, amount, permit);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
    }

    /// @inheritdoc ICSModule
    function addValidatorKeysWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        ICSAccounting.PermitInput calldata permit
    ) external whenResumed {
        _checkCanAddKeys(nodeOperatorId, from);

        ICSAccounting _accounting = accounting();

        uint256 amount = _accounting.getRequiredBondForNextKeysWstETH(
            nodeOperatorId,
            keysCount
        );

        if (amount != 0) {
            _accounting.depositWstETH(from, nodeOperatorId, amount, permit);
        }

        _addKeysAndUpdateDepositableValidatorsCount(
            nodeOperatorId,
            keysCount,
            publicKeys,
            signatures
        );
    }

    /// @inheritdoc ICSModule
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

    /// @inheritdoc ICSModule
    function confirmNodeOperatorManagerAddressChange(
        uint256 nodeOperatorId
    ) external {
        NOAddresses.confirmNodeOperatorManagerAddressChange(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc ICSModule
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

    /// @inheritdoc ICSModule
    function confirmNodeOperatorRewardAddressChange(
        uint256 nodeOperatorId
    ) external {
        NOAddresses.confirmNodeOperatorRewardAddressChange(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc ICSModule
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external {
        NOAddresses.resetNodeOperatorManagerAddress(
            _nodeOperators,
            nodeOperatorId
        );
    }

    /// @inheritdoc ICSModule
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
    /// @dev This method is not used in CSM, hence it does nothing
    /// @dev NOTE: No role checks because of empty body to save bytecode.
    function onExitedAndStuckValidatorsCountsUpdated() external {
        // solhint-disable-previous-line no-empty-blocks
        // Nothing to do, rewards are distributed by a performance oracle.
    }

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

            // @dev No need to safe cast due to conditions above
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

    /// @inheritdoc ICSModule
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
            isFullyCharged = accounting().chargeFee(
                nodeOperatorId,
                amountToCharge
            );
            emit KeyRemovalChargeApplied(nodeOperatorId);
        }

        // @dev No need to safe cast due to checks in the func above
        no.totalAddedKeys = uint32(newTotalSigningKeys);
        emit TotalSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        // @dev No need to safe cast due to checks in the func above
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

    /// @inheritdoc ICSModule
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external {
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc ICSModule
    function migrateToPriorityQueue(uint256 nodeOperatorId) external {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        if (no.usedPriorityQueue) {
            revert PriorityQueueAlreadyUsed();
        }

        uint256 curveId = _getBondCurveId(nodeOperatorId);
        (uint32 priority, uint32 maxDeposits) = PARAMETERS_REGISTRY
            .getQueueConfig(curveId);

        if (priority == QUEUE_LOWEST_PRIORITY) {
            revert NotEligibleForPriorityQueue();
        }

        uint32 enqueued = no.enqueuedCount;
        if (enqueued == 0) {
            revert NoQueuedKeysToMigrate();
        }

        uint32 deposited = no.totalDepositedKeys;
        if (maxDeposits <= deposited) {
            revert PriorityQueueMaxDepositsUsed();
        }

        uint32 toMigrate = uint32(Math.min(enqueued, maxDeposits - deposited));
        _enqueueNodeOperatorKeys(nodeOperatorId, priority, toMigrate);
        no.usedPriorityQueue = true;
        _incrementModuleNonce();

        // An alternative version to fit into the bytecode requirements is below. Please consider
        // the described caveat of the approach.

        // NOTE: We allow a node operator (NO) to reset their enqueued counter to zero only once to
        // migrate their keys from the legacy queue to a priority queue, if any. As a downside, the
        // node operator effectively can have their seats doubled in the queue.
        // Let's say we have a priority queue with a maximum of 10 deposits. Imagine a NO has 20
        // keys queued in the legacy queue. Then, the NO calls this method and gets their enqueued
        // counter reset to zero. As a result, the module will place 10 keys into the priority queue
        // and 10 more keys at the end of the overall queue. The original batches are kept in the
        // queue, so in total, the NO will have batches with 40 keys queued altogether.
        // _nodeOperators[nodeOperatorId].enqueuedCount = 0;
        // _enqueueNodeOperatorKeys(nodeOperatorId);
    }

    /// @inheritdoc ICSModule
    function reportELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        bytes32 blockHash,
        uint256 amount
    ) external onlyRole(REPORT_EL_REWARDS_STEALING_PENALTY_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 curveId = _getBondCurveId(nodeOperatorId);
        uint256 additionalFine = PARAMETERS_REGISTRY
            .getElRewardsStealingAdditionalFine(curveId);
        accounting().lockBondETH(nodeOperatorId, amount + additionalFine);

        emit ELRewardsStealingPenaltyReported(
            nodeOperatorId,
            blockHash,
            amount
        );

        // Nonce should be updated if depositableValidators change
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc ICSModule
    function cancelELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyRole(REPORT_EL_REWARDS_STEALING_PENALTY_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        accounting().releaseLockedBondETH(nodeOperatorId, amount);

        emit ELRewardsStealingPenaltyCancelled(nodeOperatorId, amount);

        // Nonce should be updated if depositableValidators change
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc ICSModule
    function settleELRewardsStealingPenalty(
        uint256[] calldata nodeOperatorIds,
        uint256[] calldata maxAmounts
    ) external onlyRole(SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE) {
        if (nodeOperatorIds.length != maxAmounts.length) {
            revert InvalidInput();
        }
        ICSAccounting _accounting = accounting();
        for (uint256 i; i < nodeOperatorIds.length; ++i) {
            uint256 nodeOperatorId = nodeOperatorIds[i];
            _onlyExistingNodeOperator(nodeOperatorId);

            uint256 locked = _accounting.getActualLockedBond(nodeOperatorId);
            if (locked == 0 || locked > maxAmounts[i]) {
                continue; // skip this NO if the locked bond is greater than the max amount or there is no locked bond
            }

            _accounting.settleLockedBondETH(nodeOperatorId);
            emit ELRewardsStealingPenaltySettled(nodeOperatorId);

            _onUncompensatedPenalty(nodeOperatorId);

            // Nonce should be updated if depositableValidators change
            _updateDepositableValidatorsCount({
                nodeOperatorId: nodeOperatorId,
                incrementNonceIfUpdated: true
            });
        }
    }

    /// @inheritdoc ICSModule
    function compensateELRewardsStealingPenalty(
        uint256 nodeOperatorId
    ) external payable {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        accounting().compensateLockedBondETH{ value: msg.value }(
            nodeOperatorId
        );

        emit ELRewardsStealingPenaltyCompensated(nodeOperatorId, msg.value);

        // Nonce should be updated if depositableValidators change
        _updateDepositableValidatorsCount({
            nodeOperatorId: nodeOperatorId,
            incrementNonceIfUpdated: true
        });
    }

    /// @inheritdoc ICSModule
    function submitWithdrawals(
        ValidatorWithdrawalInfo[] calldata withdrawalsInfo
    ) external onlyRole(VERIFIER_ROLE) {
        bool anySubmission = false;

        for (uint256 i; i < withdrawalsInfo.length; ++i) {
            ValidatorWithdrawalInfo memory withdrawalInfo = withdrawalsInfo[i];

            // For slashed validator this value should reflect pre-slashing, hence non-zero balance.
            // For non-slashed validator it will reflect the withdrawal amount, hence it cannot be zero either.
            if (withdrawalInfo.exitBalance == 0) {
                revert ZeroExitBalance();
            }

            _onlyExistingNodeOperator(withdrawalInfo.nodeOperatorId);
            NodeOperator storage no = _nodeOperators[
                withdrawalInfo.nodeOperatorId
            ];

            if (withdrawalInfo.keyIndex >= no.totalDepositedKeys) {
                revert SigningKeysInvalidOffset();
            }

            uint256 pointer = _keyPointer(
                withdrawalInfo.nodeOperatorId,
                withdrawalInfo.keyIndex
            );
            if (_isValidatorWithdrawn[pointer]) {
                continue;
            }

            anySubmission = true;

            _isValidatorWithdrawn[pointer] = true;
            unchecked {
                ++no.totalWithdrawnKeys;
            }

            bytes memory pubkey = SigningKeys.loadKeys(
                withdrawalInfo.nodeOperatorId,
                withdrawalInfo.keyIndex,
                1
            );

            // solhint-disable-next-line func-named-parameters
            emit WithdrawalSubmitted(
                withdrawalInfo.nodeOperatorId,
                withdrawalInfo.keyIndex,
                withdrawalInfo.exitBalance,
                withdrawalInfo.slashingPenalty,
                pubkey
            );

            uint256 penaltySum;
            // penaltyMultiplier is >= 1
            uint256 penaltyMultiplier = Math.max(
                withdrawalInfo.exitBalance,
                MIN_ACTIVATION_BALANCE
            ) / PENALTY_QUOTIENT;
            // It's rather unlikely that the value will exceed 64 because anything above maximum effective balance of a
            // validator will likely be withdrawn while it waits for a withdrawal. The introduced limit makes it
            // possible to use unchecked blocks below and acts as an additional limiting factor.
            penaltyMultiplier = Math.min(
                MAX_PENALTY_MULTIPLIER,
                penaltyMultiplier
            );

            bool chargeWithdrawalRequestFee;

            // It is safe to use unchecked for penalty sum because base penalties and fees are limited to uint248 in the
            // MarkedUint248 structures used to store them, and the maximum multiplier is limited to 64, so
            // `type(uint248).max * 64 * 2 < type(uint256).max`.
            ExitPenaltyInfo memory exitPenaltyInfo = EXIT_PENALTIES
                .getExitPenaltyInfo(withdrawalInfo.nodeOperatorId, pubkey);
            if (exitPenaltyInfo.delayPenalty.isValue) {
                unchecked {
                    penaltySum +=
                        exitPenaltyInfo.delayPenalty.value *
                        penaltyMultiplier;
                }
                chargeWithdrawalRequestFee = true;
            }
            if (exitPenaltyInfo.strikesPenalty.isValue) {
                unchecked {
                    penaltySum +=
                        exitPenaltyInfo.strikesPenalty.value *
                        penaltyMultiplier;
                }
                chargeWithdrawalRequestFee = true;
            }

            ICSAccounting _accounting = accounting();
            bool isFullyBurned = true;
            bool isFullyCharged = true;

            // The withdrawal request fee is taken only if the penalty is applied if no penalty, the
            // fee has been paid by the node operator on the withdrawal trigger, or it is the DAO
            // decision to withdraw the validator before that the withdrawal request becomes
            // delayed.
            if (
                chargeWithdrawalRequestFee &&
                exitPenaltyInfo.withdrawalRequestFee.value != 0
            ) {
                isFullyCharged = _accounting.chargeFee(
                    withdrawalInfo.nodeOperatorId,
                    exitPenaltyInfo.withdrawalRequestFee.value
                );
            }

            if (withdrawalInfo.slashingPenalty > 0) {
                // Slashing penalty doesn't scale because all the losses are already accounted.
                penaltySum += withdrawalInfo.slashingPenalty;
            } else if (withdrawalInfo.exitBalance < MIN_ACTIVATION_BALANCE) {
                // type(uint248).max * 64 * 2 + 32 * 10**18 < type(uint256).max
                unchecked {
                    penaltySum +=
                        MIN_ACTIVATION_BALANCE -
                        withdrawalInfo.exitBalance;
                }
            }

            if (penaltySum > 0) {
                isFullyBurned = _accounting.penalize(
                    withdrawalInfo.nodeOperatorId,
                    penaltySum
                );
            }

            if (!isFullyCharged || !isFullyBurned) {
                _onUncompensatedPenalty(withdrawalInfo.nodeOperatorId);
            }

            // Nonce will be updated below even if depositable count was not changed
            _updateDepositableValidatorsCount({
                nodeOperatorId: withdrawalInfo.nodeOperatorId,
                incrementNonceIfUpdated: false
            });
        }

        if (anySubmission) {
            _incrementModuleNonce();
        }
    }

    /// @inheritdoc IStakingModule
    /// @dev Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
    ///      DSM will unvet current keys due to nonce change.
    ///      The key removal charge should be reset to 0 manually by the DAO to allow Node Operators to remove the keys without any charge.
    ///      After keys removal the DAO should set the new key removal charge.
    function onWithdrawalCredentialsChanged()
        external
        onlyRole(STAKING_ROUTER_ROLE)
    {
        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    function reportValidatorExitDelay(
        uint256 nodeOperatorId,
        uint256 /* proofSlotTimestamp */,
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

    /// @inheritdoc IStakingModule
    /// @notice Get the next `depositsCount` of depositable keys with signatures from the queue
    /// @dev The method does not update depositable keys count for the Node Operators before the queue processing start.
    ///      Hence, in the rare cases of negative stETH rebase the method might return unbonded keys. This is a trade-off
    ///      between the gas cost and the correctness of the data. Due to module design, any unbonded keys will be requested
    ///      to exit by VEBO.
    /// @dev Second param `depositCalldata` is not used
    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata /* depositCalldata */
    )
        external
        virtual
        onlyRole(STAKING_ROUTER_ROLE)
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(depositsCount);
        if (depositsCount == 0) {
            return (publicKeys, signatures);
        }

        uint256 depositsLeft = depositsCount;
        uint256 loadedKeysCount = 0;

        QueueLib.Queue storage queue;
        // Note: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY || depositsLeft == 0) {
                break;
            }

            queue = _getQueue(priority);
            unchecked {
                // Note: unused below
                ++priority;
            }

            for (
                Batch item = queue.peek();
                !item.isNil();
                item = queue.peek()
            ) {
                // NOTE: see the `enqueuedCount` note below.
                unchecked {
                    uint256 noId = item.noId();
                    uint256 keysInBatch = item.keys();
                    NodeOperator storage no = _nodeOperators[noId];

                    uint256 keysCount = Math.min(
                        Math.min(no.depositableValidatorsCount, keysInBatch),
                        depositsLeft
                    );
                    // `depositsLeft` is non-zero at this point all the time, so the check `depositsLeft > keysCount`
                    // covers the case when no depositable keys on the Node Operator have been left.
                    if (depositsLeft > keysCount || keysCount == keysInBatch) {
                        // NOTE: `enqueuedCount` >= keysInBatch invariant should be checked.
                        // @dev No need to safe cast due to internal logic
                        no.enqueuedCount -= uint32(keysInBatch);
                        // We've consumed all the keys in the batch, so we dequeue it.
                        queue.dequeue();
                    } else {
                        // This branch covers the case when we stop in the middle of the batch.
                        // We release the amount of keys consumed only, the rest will be kept.
                        // @dev No need to safe cast due to internal logic
                        no.enqueuedCount -= uint32(keysCount);
                        // NOTE: `keysInBatch` can't be less than `keysCount` at this point.
                        // We update the batch with the remaining keys.
                        item = item.setKeys(keysInBatch - keysCount);
                        // Store the updated batch back to the queue.
                        queue.queue[queue.head] = item;
                    }

                    // Note: This condition is located here to allow for the correct removal of the batch for the Node Operators with no depositable keys
                    if (keysCount == 0) {
                        continue;
                    }

                    // solhint-disable-next-line func-named-parameters
                    SigningKeys.loadKeysSigs(
                        noId,
                        no.totalDepositedKeys,
                        keysCount,
                        publicKeys,
                        signatures,
                        loadedKeysCount
                    );

                    // It's impossible in practice to reach the limit of these variables.
                    loadedKeysCount += keysCount;
                    // @dev No need to safe cast due to internal logic
                    uint32 totalDepositedKeys = no.totalDepositedKeys +
                        uint32(keysCount);
                    no.totalDepositedKeys = totalDepositedKeys;

                    emit DepositedSigningKeysCountChanged(
                        noId,
                        totalDepositedKeys
                    );

                    // No need for `_updateDepositableValidatorsCount` call since we update the number directly.
                    // `keysCount` is min of `depositableValidatorsCount` and `depositsLeft`.
                    // @dev No need to safe cast due to internal logic
                    uint32 newCount = no.depositableValidatorsCount -
                        uint32(keysCount);
                    no.depositableValidatorsCount = newCount;
                    emit DepositableSigningKeysCountChanged(noId, newCount);

                    depositsLeft -= keysCount;
                    if (depositsLeft == 0) {
                        break;
                    }
                }
            }
        }

        if (loadedKeysCount != depositsCount) {
            revert NotEnoughKeys();
        }

        unchecked {
            // @dev depositsCount can not overflow in practice due to memory and gas limits
            _depositableValidatorsCount -= uint64(depositsCount);
            _totalDepositedValidators += uint64(depositsCount);
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function cleanDepositQueue(
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth) {
        removed = 0;
        lastRemovedAtDepth = 0;

        if (maxItems == 0) {
            return (0, 0);
        }

        // NOTE: We need one unique hash map per function invocation to be able to track batches of
        // the same operator across multiple queues.
        TransientUintUintMap queueLookup = TransientUintUintMapLib.create();

        QueueLib.Queue storage queue;

        uint256 totalVisited = 0;
        // Note: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY) {
                break;
            }

            queue = _getQueue(priority);
            unchecked {
                ++priority;
            }

            (
                uint256 removedPerQueue,
                uint256 lastRemovedAtDepthPerQueue,
                uint256 visitedPerQueue,
                bool reachedOutOfQueue
            ) = queue.clean(_nodeOperators, maxItems, queueLookup);

            if (removedPerQueue > 0) {
                unchecked {
                    // 1234 56 789A     <- cumulative depth (A=10)
                    // 1234 12 1234     <- depth per queue
                    // **R*|**|**R*     <- queue with [R]emoved elements
                    //
                    // Given that we observed all 3 queues:
                    // totalVisited: 4+2=6
                    // lastRemovedAtDepthPerQueue: 3
                    // lastRemovedAtDepth: 6+3=9

                    lastRemovedAtDepth =
                        totalVisited +
                        lastRemovedAtDepthPerQueue;
                    removed += removedPerQueue;
                }
            }

            // NOTE: If `maxItems` is set to the total length of the queue(s), `reachedOutOfQueue` is equal
            // to `false`, effectively breaking the cycle, because in `QueueLib.clean` we don't reach
            // an empty batch after the end of a queue.
            if (!reachedOutOfQueue) {
                break;
            }

            unchecked {
                totalVisited += visitedPerQueue;
                maxItems -= visitedPerQueue;
            }
        }
    }

    /// @inheritdoc ICSModule
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc ICSModule
    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail) {
        QueueLib.Queue storage q = _getQueue(queuePriority);
        return (q.head, q.tail);
    }

    /// @inheritdoc ICSModule
    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch) {
        return _getQueue(queuePriority).at(index);
    }

    /// @inheritdoc ICSModule
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

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        returns (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {
        totalExitedValidators = _totalExitedValidators;
        totalDepositedValidators = _totalDepositedValidators;
        depositableValidatorsCount = _depositableValidatorsCount;
    }

    /// @inheritdoc ICSModule
    function getNodeOperator(
        uint256 nodeOperatorId
    ) external view returns (NodeOperator memory) {
        return _nodeOperators[nodeOperatorId];
    }

    /// @inheritdoc ICSModule
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

    /// @inheritdoc ICSModule
    function getNodeOperatorOwner(
        uint256 nodeOperatorId
    ) external view returns (address) {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        return
            no.extendedManagerPermissions
                ? no.managerAddress
                : no.rewardAddress;
    }

    /// @inheritdoc ICSModule
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
        _onlyExistingNodeOperator(nodeOperatorId);
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        uint256 totalUnbondedKeys = accounting().getUnbondedKeysCountToEject(
            nodeOperatorId
        );
        uint256 totalNonDepositedKeys = no.totalAddedKeys -
            no.totalDepositedKeys;
        // Unbonded deposited keys
        if (totalUnbondedKeys > totalNonDepositedKeys) {
            targetLimitMode = FORCED_TARGET_LIMIT_MODE_ID;
            // If there is `targetLimit` set no matter the `targetLimitMode` we switch to `FORCED_TARGET_LIMIT_MODE`
            // to ensure that there is no way to bypass the regular limit by having unbonded keys.
            unchecked {
                targetValidatorsCount =
                    no.totalAddedKeys -
                    no.totalWithdrawnKeys -
                    totalUnbondedKeys;
            }
            // Account for the no.targetLimit only when target limit is enabled
            if (no.targetLimitMode > 0) {
                targetValidatorsCount = Math.min(
                    targetValidatorsCount,
                    no.targetLimit
                );
            }
        } else {
            targetLimitMode = no.targetLimitMode;
            targetValidatorsCount = no.targetLimit;
        }
        stuckValidatorsCount = 0;
        refundedValidatorsCount = 0;
        stuckPenaltyEndTimestamp = 0;
        totalExitedValidators = no.totalExitedKeys;
        totalDepositedValidators = no.totalDepositedKeys;
        depositableValidatorsCount = no.depositableValidatorsCount;
    }

    /// @inheritdoc ICSModule
    function getNodeOperatorTotalDepositedKeys(
        uint256 nodeOperatorId
    ) external view returns (uint256 totalDepositedKeys) {
        totalDepositedKeys = _nodeOperators[nodeOperatorId].totalDepositedKeys;
    }

    /// @inheritdoc ICSModule
    function getSigningKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory) {
        _onlyValidIndexRange(nodeOperatorId, startIndex, keysCount);

        return SigningKeys.loadKeys(nodeOperatorId, startIndex, keysCount);
    }

    /// @inheritdoc ICSModule
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
            return new uint256[](0);
        }

        uint256 idsCount = limit < nodeOperatorsCount - offset
            ? limit
            : nodeOperatorsCount - offset;
        nodeOperatorIds = new uint256[](idsCount);
        for (uint256 i = 0; i < nodeOperatorIds.length; ++i) {
            nodeOperatorIds[i] = offset + i;
        }
    }

    /// @inheritdoc IStakingModule
    function isValidatorExitDelayPenaltyApplicable(
        uint256 nodeOperatorId,
        uint256 /* proofSlotTimestamp */,
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

    /// @dev This function is used to get the accounting contract from immutables to save bytecode and for backwards compatibility
    function accounting() public view returns (ICSAccounting) {
        return ACCOUNTING;
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
        _forgetOperatorCreator(nodeOperatorId);

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
                // @dev No need to safe cast due to internal logic
                totalVettedKeys = totalVettedKeys + uint32(keysCount);
                no.totalVettedKeys = totalVettedKeys;
                emit VettedSigningKeysCountChanged(
                    nodeOperatorId,
                    totalVettedKeys
                );
            }

            // @dev No need to safe cast due to internal logic
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
            _totalExitedValidators =
                (_totalExitedValidators - totalExitedKeys) +
                uint64(exitedValidatorsCount);
        }
        // @dev No need to safe cast due to conditions above
        no.totalExitedKeys = uint32(exitedValidatorsCount);

        emit ExitedSigningKeysCountChanged(
            nodeOperatorId,
            exitedValidatorsCount
        );
    }

    function _updateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        bool incrementNonceIfUpdated
    ) internal {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        uint32 totalDepositedKeys = no.totalDepositedKeys;
        uint256 newCount = no.totalVettedKeys - totalDepositedKeys;
        uint256 unbondedKeys = accounting().getUnbondedKeysCount(
            nodeOperatorId
        );

        {
            uint256 nonDeposited = no.totalAddedKeys - totalDepositedKeys;
            if (unbondedKeys >= nonDeposited) {
                newCount = 0;
            } else if (unbondedKeys > no.totalAddedKeys - no.totalVettedKeys) {
                newCount = nonDeposited - unbondedKeys;
            }
        }

        if (no.targetLimitMode > 0 && newCount > 0) {
            unchecked {
                uint256 nonWithdrawnValidators = totalDepositedKeys -
                    no.totalWithdrawnKeys;
                newCount = Math.min(
                    no.targetLimit > nonWithdrawnValidators
                        ? no.targetLimit - nonWithdrawnValidators
                        : 0,
                    newCount
                );
            }
        }

        if (no.depositableValidatorsCount != newCount) {
            // Updating the global counter.
            // @dev No need to safe cast due to internal logic
            unchecked {
                _depositableValidatorsCount =
                    _depositableValidatorsCount -
                    no.depositableValidatorsCount +
                    uint64(newCount);
            }
            // @dev No need to safe cast due to internal logic
            no.depositableValidatorsCount = uint32(newCount);
            emit DepositableSigningKeysCountChanged(nodeOperatorId, newCount);
            if (incrementNonceIfUpdated) {
                _incrementModuleNonce();
            }
            _enqueueNodeOperatorKeys(nodeOperatorId);
        }
    }

    function _enqueueNodeOperatorKeys(uint256 nodeOperatorId) internal {
        uint256 curveId = _getBondCurveId(nodeOperatorId);
        (uint32 priority, uint32 maxDeposits) = PARAMETERS_REGISTRY
            .getQueueConfig(curveId);

        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        uint32 depositable = no.depositableValidatorsCount;
        uint32 enqueued = no.enqueuedCount;
        if (depositable <= enqueued) {
            return;
        }

        uint32 toEnqueue;
        unchecked {
            toEnqueue = depositable - enqueued;
        }

        if (priority < QUEUE_LOWEST_PRIORITY) {
            unchecked {
                uint32 depositedAndQueued = no.totalDepositedKeys + enqueued;
                if (maxDeposits > depositedAndQueued) {
                    uint32 priorityDepositsLeft = maxDeposits -
                        depositedAndQueued;
                    uint32 count = uint32(
                        Math.min(toEnqueue, priorityDepositsLeft)
                    );

                    _enqueueNodeOperatorKeys(nodeOperatorId, priority, count);
                    toEnqueue -= count;

                    if (!no.usedPriorityQueue) {
                        no.usedPriorityQueue = true;
                    }
                }
            }
        }

        if (toEnqueue > 0) {
            _enqueueNodeOperatorKeys(
                nodeOperatorId,
                QUEUE_LOWEST_PRIORITY,
                toEnqueue
            );
        }
    }

    // NOTE: If `count` is 0 an empty batch will be created.
    function _enqueueNodeOperatorKeys(
        uint256 nodeOperatorId,
        uint256 queuePriority,
        uint32 count
    ) internal {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        no.enqueuedCount += count;
        QueueLib.Queue storage q = _getQueue(queuePriority);
        q.enqueue(nodeOperatorId, count);
        emit BatchEnqueued(queuePriority, nodeOperatorId, count);
    }

    function _recordOperatorCreator(uint256 nodeOperatorId) internal {
        TransientUintUintMap map = TransientUintUintMapLib.load(
            OPERATORS_CREATED_IN_TX_MAP_TSLOT
        );

        map.set(nodeOperatorId, uint256(uint160(msg.sender)));
    }

    function _forgetOperatorCreator(uint256 nodeOperatorId) internal {
        TransientUintUintMap map = TransientUintUintMapLib.load(
            OPERATORS_CREATED_IN_TX_MAP_TSLOT
        );
        map.set(nodeOperatorId, 0);
    }

    function _setTargetLimit(
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) internal {
        if (targetLimitMode > FORCED_TARGET_LIMIT_MODE_ID) {
            revert InvalidInput();
        }
        if (targetLimit > type(uint32).max) {
            revert InvalidInput();
        }
        _onlyExistingNodeOperator(nodeOperatorId);

        if (targetLimitMode == 0) {
            targetLimit = 0;
        }

        NodeOperator storage no = _nodeOperators[nodeOperatorId];

        // NOTE: Bytecode saving trick; increased gas cost in rare cases is fine.
        // if (
        //     no.targetLimitMode == targetLimitMode &&
        //     no.targetLimit == targetLimit
        // ) {
        //     return;
        // }

        // @dev No need to safe cast due to conditions above
        no.targetLimitMode = uint8(targetLimitMode);
        no.targetLimit = uint32(targetLimit);

        emit TargetValidatorsCountChanged(
            nodeOperatorId,
            targetLimitMode,
            targetLimit
        );
    }

    function _getOperatorCreator(
        uint256 nodeOperatorId
    ) internal view returns (address) {
        TransientUintUintMap map = TransientUintUintMapLib.load(
            OPERATORS_CREATED_IN_TX_MAP_TSLOT
        );
        return address(uint160(map.get(nodeOperatorId)));
    }

    /// @dev Acts as a proxy to `_queueByPriority` till `_legacyQueue` deprecation.
    /// @dev TODO: Remove the method in the next major release.
    function _getQueue(
        uint256 priority
    ) internal view returns (QueueLib.Queue storage q) {
        if (priority == QUEUE_LEGACY_PRIORITY) {
            assembly {
                q.slot := _legacyQueue.slot
            }
        } else {
            q = _queueByPriority[priority];
        }
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
            if (_getOperatorCreator(nodeOperatorId) != msg.sender) {
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
        return accounting().getBondCurveId(nodeOperatorId);
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
