// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IStakingModule } from "./IStakingModule.sol";
import { ICSAccounting } from "./ICSAccounting.sol";
import { IQueueLib } from "../lib/QueueLib.sol";
import { INOAddresses } from "../lib/NOAddresses.sol";
import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";
import { Batch } from "../lib/QueueLib.sol";
import { ILidoLocator } from "./ILidoLocator.sol";
import { IStETH } from "./IStETH.sol";
import { ICSParametersRegistry } from "./ICSParametersRegistry.sol";
import { ICSExitPenalties } from "./ICSExitPenalties.sol";

struct NodeOperator {
    // All the counters below are used together e.g. in the _updateDepositableValidatorsCount
    /* 1 */ uint32 totalAddedKeys; // @dev increased and decreased when removed
    /* 1 */ uint32 totalWithdrawnKeys; // @dev only increased
    /* 1 */ uint32 totalDepositedKeys; // @dev only increased
    /* 1 */ uint32 totalVettedKeys; // @dev both increased and decreased
    /* 1 */ uint32 stuckValidatorsCount; // @dev both increased and decreased
    /* 1 */ uint32 depositableValidatorsCount; // @dev any value
    /* 1 */ uint32 targetLimit;
    /* 1 */ uint8 targetLimitMode;
    /* 2 */ uint32 totalExitedKeys; // @dev only increased except for the unsafe updates
    /* 2 */ uint32 enqueuedCount; // Tracks how many places are occupied by the node operator's keys in the queue.
    /* 2 */ address managerAddress;
    /* 3 */ address proposedManagerAddress;
    /* 4 */ address rewardAddress;
    /* 5 */ address proposedRewardAddress;
    /* 5 */ bool extendedManagerPermissions;
    /* 5 */ bool usedPriorityQueue;
}

struct NodeOperatorManagementProperties {
    address managerAddress;
    address rewardAddress;
    bool extendedManagerPermissions;
}

struct ValidatorWithdrawalInfo {
    uint256 nodeOperatorId;
    // Index of the withdrawn key in the Node Operator's keys storage.
    uint256 keyIndex;
    // Balance to be used to calculate penalties. For a regular withdrawal of a validator it's the withdrawal amount.
    // For a slashed validator it's its balance before slashing. The balance will be used to scale incurred penalties.
    uint256 exitBalance;
    // Amount of ETH/stETH to penalize Node Operator due to slashing. If the value is non-zero, it means the validator
    // was slashed.
    uint256 slashingPenalty;
}

/// @title Lido's Community Staking Module interface
interface ICSModule is
    IQueueLib,
    INOAddresses,
    IAssetRecovererLib,
    IStakingModule
{
    error CannotAddKeys();
    error NodeOperatorDoesNotExist();
    error SenderIsNotEligible();
    error InvalidVetKeysPointer();
    error ExitedKeysHigherThanTotalDeposited();
    error ExitedKeysDecrease();
    error ZeroExitBalance();

    error InvalidInput();
    error NotEnoughKeys();
    error PriorityQueueAlreadyUsed();
    error NotEligibleForPriorityQueue();
    error PriorityQueueMaxDepositsUsed();
    error NoQueuedKeysToMigrate();

    error KeysLimitExceeded();
    error SigningKeysInvalidOffset();

    error InvalidAmount();

    error ZeroLocatorAddress();
    error ZeroAccountingAddress();
    error ZeroExitPenaltiesAddress();
    error ZeroAdminAddress();
    error ZeroSenderAddress();
    error ZeroParametersRegistryAddress();

    event NodeOperatorAdded(
        uint256 indexed nodeOperatorId,
        address indexed managerAddress,
        address indexed rewardAddress,
        bool extendedManagerPermissions
    );
    event ReferrerSet(uint256 indexed nodeOperatorId, address indexed referrer);
    event DepositableSigningKeysCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 depositableKeysCount
    );
    event VettedSigningKeysCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 vettedKeysCount
    );
    event VettedSigningKeysCountDecreased(uint256 indexed nodeOperatorId);
    event DepositedSigningKeysCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 depositedKeysCount
    );
    event ExitedSigningKeysCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 exitedKeysCount
    );
    event TotalSigningKeysCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 totalKeysCount
    );
    event TargetValidatorsCountChanged(
        uint256 indexed nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetValidatorsCount
    );
    event WithdrawalSubmitted(
        uint256 indexed nodeOperatorId,
        uint256 keyIndex,
        uint256 exitBalance,
        uint256 slashingPenalty,
        bytes pubkey
    );

    event BatchEnqueued(
        uint256 indexed queuePriority,
        uint256 indexed nodeOperatorId,
        uint256 count
    );

    event KeyRemovalChargeApplied(uint256 indexed nodeOperatorId);
    event ELRewardsStealingPenaltyReported(
        uint256 indexed nodeOperatorId,
        bytes32 proposedBlockHash,
        uint256 stolenAmount
    );
    event ELRewardsStealingPenaltyCancelled(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event ELRewardsStealingPenaltyCompensated(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event ELRewardsStealingPenaltySettled(uint256 indexed nodeOperatorId);

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function STAKING_ROUTER_ROLE() external view returns (bytes32);

    function REPORT_EL_REWARDS_STEALING_PENALTY_ROLE()
        external
        view
        returns (bytes32);

    function SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE()
        external
        view
        returns (bytes32);

    function VERIFIER_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    function CREATE_NODE_OPERATOR_ROLE() external view returns (bytes32);

    function MIN_ACTIVATION_BALANCE() external view returns (uint256);

    function PENALTY_QUOTIENT() external view returns (uint256);

    function LIDO_LOCATOR() external view returns (ILidoLocator);

    function STETH() external view returns (IStETH);

    function PARAMETERS_REGISTRY()
        external
        view
        returns (ICSParametersRegistry);

    function ACCOUNTING() external view returns (ICSAccounting);

    function EXIT_PENALTIES() external view returns (ICSExitPenalties);

    function FEE_DISTRIBUTOR() external view returns (address);

    function QUEUE_LOWEST_PRIORITY() external view returns (uint256);

    function QUEUE_LEGACY_PRIORITY() external view returns (uint256);

    /// @notice Returns the address of the accounting contract
    function accounting() external view returns (ICSAccounting);

    /// @notice Pause creation of the Node Operators and keys upload for `duration` seconds.
    ///         Existing NO management and reward claims are still available.
    ///         To pause reward claims use pause method on CSAccounting
    /// @param duration Duration of the pause in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Resume creation of the Node Operators and keys upload
    function resume() external;

    /// @notice Returns the initialized version of the contract
    function getInitializedVersion() external view returns (uint64);

    /// @notice Permissioned method to add a new Node Operator
    ///         Should be called by `*Gate.sol` contracts. See `PermissionlessGate.sol` and `VettedGate.sol` for examples
    /// @param from Sender address. Initial sender address to be used as a default manager and reward addresses.
    ///             Gates must pass the correct address in order to specify which address should be the owner of the Node Operator.
    /// @param managementProperties Optional. Management properties to be used for the Node Operator.
    ///                             managerAddress: Used as `managerAddress` for the Node Operator. If not passed `from` will be used.
    ///                             rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `from` will be used.
    ///                             extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`.
    ///                                                         If set to true `resetNodeOperatorManagerAddress` method will be disabled
    /// @param referrer Optional. Referrer address. Should be passed when Node Operator is created using partners integration
    function createNodeOperator(
        address from,
        NodeOperatorManagementProperties memory managementProperties,
        address referrer
    ) external returns (uint256 nodeOperatorId);

    /// @notice Add new keys to the existing Node Operator using ETH as a bond
    /// @param from Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keysCount Signing keys count
    /// @param publicKeys Public keys to submit
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples
    ///                   https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata
    function addValidatorKeysETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures
    ) external payable;

    /// @notice Add new keys to the existing Node Operator using stETH as a bond
    /// @notice Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert
    /// @param from Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keysCount Signing keys count
    /// @param publicKeys Public keys to submit
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples
    ///                   https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata
    /// @param permit Optional. Permit to use stETH as bond
    function addValidatorKeysStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        ICSAccounting.PermitInput memory permit
    ) external;

    /// @notice Add new keys to the existing Node Operator using wstETH as a bond
    /// @notice Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert
    /// @param from Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keysCount Signing keys count
    /// @param publicKeys Public keys to submit
    /// @param signatures Signatures of `(deposit_message_root, domain)` tuples
    ///                   https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata
    /// @param permit Optional. Permit to use wstETH as bond
    function addValidatorKeysWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes memory publicKeys,
        bytes memory signatures,
        ICSAccounting.PermitInput memory permit
    ) external;

    /// @notice Report EL rewards stealing for the given Node Operator
    /// @notice The final locked amount will be equal to the stolen funds plus EL stealing additional fine
    /// @param nodeOperatorId ID of the Node Operator
    /// @param blockHash Execution layer block hash of the proposed block with EL rewards stealing
    /// @param amount Amount of stolen EL rewards in ETH
    function reportELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        bytes32 blockHash,
        uint256 amount
    ) external;

    /// @notice Compensate EL rewards stealing penalty for the given Node Operator to prevent further validator exits
    /// @dev Can only be called by the Node Operator manager
    /// @param nodeOperatorId ID of the Node Operator
    function compensateELRewardsStealingPenalty(
        uint256 nodeOperatorId
    ) external payable;

    /// @notice Cancel previously reported and not settled EL rewards stealing penalty for the given Node Operator
    /// @notice The funds will be unlocked
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount of penalty to cancel
    function cancelELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external;

    /// @notice Settles locked bond and sets the target limit to 0 or the given Node Operators
    /// @dev SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE role is expected to be assigned to Easy Track
    /// @param nodeOperatorIds IDs of the Node Operators
    /// @param maxAmounts Maximum amounts to settle for each Node Operator
    function settleELRewardsStealingPenalty(
        uint256[] memory nodeOperatorIds,
        uint256[] memory maxAmounts
    ) external;

    /// @notice Propose a new manager address for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed manager address
    function proposeNodeOperatorManagerAddressChange(
        uint256 nodeOperatorId,
        address proposedAddress
    ) external;

    /// @notice Confirm a new manager address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorManagerAddressChange(
        uint256 nodeOperatorId
    ) external;

    /// @notice Reset the manager address to the reward address.
    ///         Should be called from the reward address
    /// @param nodeOperatorId ID of the Node Operator
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external;

    /// @notice Propose a new reward address for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed reward address
    function proposeNodeOperatorRewardAddressChange(
        uint256 nodeOperatorId,
        address proposedAddress
    ) external;

    /// @notice Confirm a new reward address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorRewardAddressChange(
        uint256 nodeOperatorId
    ) external;

    /// @notice Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newAddress Proposed reward address
    function changeNodeOperatorRewardAddress(
        uint256 nodeOperatorId,
        address newAddress
    ) external;

    /// @notice Get the pointers to the head and tail of queue with the given priority.
    /// @param queuePriority Priority of the queue to get the pointers.
    /// @return head Pointer to the head of the queue.
    /// @return tail Pointer to the tail of the queue.
    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail);

    /// @notice Get the deposit queue item by an index
    /// @param queuePriority Priority of the queue to get an item from
    /// @param index Index of a queue item
    /// @return Deposit queue item from the priority queue
    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch);

    /// @notice Clean the deposit queue from batches with no depositable keys
    /// @dev Use **eth_call** to check how many items will be removed
    /// @param maxItems How many queue items to review
    /// @return removed Count of batches to be removed by visiting `maxItems` batches
    /// @return lastRemovedAtDepth The value to use as `maxItems` to remove `removed` batches if the static call of the method was used
    function cleanDepositQueue(
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth);

    /// @notice Update depositable validators data and enqueue all unqueued keys for the given Node Operator.
    ///         Unqueued stands for vetted but not enqueued keys.
    /// @dev The following rules are applied:
    ///         - Unbonded keys can not be depositable
    ///         - Unvetted keys can not be depositable
    ///         - Depositable keys count should respect targetLimit value
    /// @param nodeOperatorId ID of the Node Operator
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external;

    /// Performs a one-time migration of allocated seats from the legacy or default queue to a priority queue
    /// for an eligible node operator. This is possible, e.g., in the following scenario: A node
    /// operator uploaded keys before CSM v2 and have no deposits due to a long queue.
    /// After the CSM v2 release, the node operator has claimed the ICS or other priority node operator type.
    /// This node operator type gives the node operator the ability to get several deposits through
    /// the priority queue. So, by calling the migration method, the node operator can obtain seats
    /// in the priority queue, even though they already have seats in the legacy queue.
    /// The method can also be used by the node operators who joined CSM v2 permissionlessly after the release
    /// and had their node operator type upgraded to ICS or another priority type.
    /// The method does not remove the old queue items. Hence, the node operator can upload additional keys that
    /// will take the place of the migrated keys in the original queue.
    /// @param nodeOperatorId ID of the Node Operator
    function migrateToPriorityQueue(uint256 nodeOperatorId) external;

    /// @notice Get Node Operator info
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator info
    function getNodeOperator(
        uint256 nodeOperatorId
    ) external view returns (NodeOperator memory);

    /// @notice Get Node Operator management properties
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator management properties
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory);

    /// @notice Get Node Operator owner. Owner is manager address if `extendedManagerPermissions` is enabled and reward address otherwise
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator owner
    function getNodeOperatorOwner(
        uint256 nodeOperatorId
    ) external view returns (address);

    /// @notice Get Node Operator non-withdrawn keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Non-withdrawn keys count
    function getNodeOperatorNonWithdrawnKeys(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get Node Operator total deposited keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Total deposited keys count
    function getNodeOperatorTotalDepositedKeys(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get Node Operator signing keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Count of keys to get
    /// @return Signing keys
    function getSigningKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory);

    /// @notice Get Node Operator signing keys with signatures
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Count of keys to get
    /// @return keys Signing keys
    /// @return signatures Signatures of `(deposit_message_root, domain)` tuples
    ///                    https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata
    function getSigningKeysWithSignatures(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory keys, bytes memory signatures);

    /// @notice Report Node Operator's keys as withdrawn and settle withdrawn amount
    /// @notice Called by `CSVerifier` contract.
    ///         See `CSVerifier.processWithdrawalProof` to use this method permissionless
    /// @param withdrawalsInfo An array for the validator withdrawals info structs
    function submitWithdrawals(
        ValidatorWithdrawalInfo[] calldata withdrawalsInfo
    ) external;

    /// @notice Check if the given Node Operator's key is reported as withdrawn
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndex index of the key to check
    /// @return Is validator reported as withdrawn or not
    function isValidatorWithdrawn(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external view returns (bool);

    /// @notice Remove keys for the Node Operator and confiscate removal charge for each deleted key
    ///         This method is a part of the Optimistic Vetting scheme. After key deletion `totalVettedKeys`
    ///         is set equal to `totalAddedKeys`. If invalid keys are not removed, the unvetting process will be repeated
    ///         and `decreaseVettedSigningKeysCount` will be called by StakingRouter.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Keys count to delete
    function removeKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external;
}
