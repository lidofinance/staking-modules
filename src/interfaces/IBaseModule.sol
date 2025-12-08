// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";
import { INOAddresses } from "../lib/NOAddresses.sol";

import { INodeOperatorOwner } from "./INodeOperatorOwner.sol";
import { IAccounting } from "./IAccounting.sol";
import { IExitPenalties } from "./IExitPenalties.sol";
import { ILidoLocator } from "./ILidoLocator.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";
import { IStakingModule } from "./IStakingModule.sol";
import { IStETH } from "./IStETH.sol";

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
    /* 5 */ bool usedPriorityQueue; // @dev no longer used, left for the storage layout compatibility
}

struct NodeOperatorManagementProperties {
    address managerAddress;
    address rewardAddress;
    bool extendedManagerPermissions;
}

struct WithdrawnValidatorInfo {
    uint256 nodeOperatorId;
    // Index of the withdrawn key in the Node Operator's keys storage.
    uint256 keyIndex;
    // Balance to be used to calculate penalties. For a regular withdrawal of a validator it's the withdrawal amount.
    // For a slashed validator it's its balance before slashing. The balance will be used to scale incurred penalties.
    uint256 exitBalance;
    // Amount of ETH/stETH to penalize Node Operator due to slashing.
    uint256 slashingPenalty;
    // Whether the validator has been slashed.
    bool isSlashed;
}

/// @notice Base module interface for repository modules such as `ICSModule` and `ICuratedModule`.
interface IBaseModule is
    IStakingModule,
    IAccessControlEnumerable,
    INOAddresses,
    IAssetRecovererLib,
    INodeOperatorOwner
{
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
    event ValidatorWithdrawn(
        uint256 indexed nodeOperatorId,
        uint256 keyIndex,
        uint256 exitBalance,
        uint256 slashingPenalty,
        bytes pubkey
    );
    event ValidatorSlashingReported(
        uint256 indexed nodeOperatorId,
        uint256 keyIndex,
        bytes pubkey
    );
    event KeyRemovalChargeApplied(uint256 indexed nodeOperatorId);

    error CannotAddKeys();
    error NodeOperatorDoesNotExist();
    error SenderIsNotEligible();
    error InvalidVetKeysPointer();
    error ExitedKeysHigherThanTotalDeposited();
    error ExitedKeysDecrease();
    error ZeroExitBalance();
    error SlashingPenaltyIsNotApplicable();
    error ValidatorSlashingAlreadyReported();
    error InvalidWithdrawnValidatorInfo();

    error InvalidAmount();
    error InvalidInput();
    error NotEnoughKeys();

    error KeysLimitExceeded();
    error SigningKeysInvalidOffset();

    error ZeroLocatorAddress();
    error ZeroAccountingAddress();
    error ZeroExitPenaltiesAddress();
    error ZeroAdminAddress();
    error ZeroSenderAddress();
    error ZeroParametersRegistryAddress();

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function STAKING_ROUTER_ROLE() external view returns (bytes32);

    function REPORT_GENERAL_DELAYED_PENALTY_ROLE()
        external
        view
        returns (bytes32);

    function SETTLE_GENERAL_DELAYED_PENALTY_ROLE()
        external
        view
        returns (bytes32);

    function VERIFIER_ROLE() external view returns (bytes32);

    function SUBMIT_WITHDRAWALS_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    function CREATE_NODE_OPERATOR_ROLE() external view returns (bytes32);

    function LIDO_LOCATOR() external view returns (ILidoLocator);

    function STETH() external view returns (IStETH);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function ACCOUNTING() external view returns (IAccounting);

    function EXIT_PENALTIES() external view returns (IExitPenalties);

    function FEE_DISTRIBUTOR() external view returns (address);

    /// @notice Pause creation of the Node Operators and keys upload for `duration` seconds.
    ///         Existing NO management and reward claims are still available.
    ///         To pause reward claims use pause method on Accounting
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
        IAccounting.PermitInput memory permit
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
        IAccounting.PermitInput memory permit
    ) external;

    /// @notice Report general delayed penalty for the given Node Operator
    /// @notice The final locked amount will be equal to the penalty amount plus additional fine
    /// @param nodeOperatorId ID of the Node Operator
    /// @param penaltyType Type of the penalty
    /// @param amount Penalty amount in ETH
    /// @param details Additional details about the penalty
    function reportGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        bytes32 penaltyType,
        uint256 amount,
        string calldata details
    ) external;

    /// @notice Compensate general delayed penalty for the given Node Operator to prevent further validator exits
    /// @dev Can only be called by the Node Operator manager
    /// @param nodeOperatorId ID of the Node Operator
    function compensateGeneralDelayedPenalty(
        uint256 nodeOperatorId
    ) external payable;

    /// @notice Cancel previously reported and not settled general delayed penalty for the given Node Operator
    /// @notice The funds will be unlocked
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount of penalty to cancel
    function cancelGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external;

    /// @notice Settles locked bond and sets the target limit to 0 or the given Node Operators
    /// @dev SETTLE_GENERAL_DELAYED_PENALTY_ROLE role is expected to be assigned to Easy Track
    /// @param nodeOperatorIds IDs of the Node Operators
    /// @param maxAmounts Maximum amounts to settle for each Node Operator
    function settleGeneralDelayedPenalty(
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

    /// @notice Update depositable validators data and enqueue all unqueued keys for the given Node Operator.
    ///         Unqueued stands for vetted but not enqueued keys.
    /// @dev The following rules are applied:
    ///         - Unbonded keys can not be depositable
    ///         - Unvetted keys can not be depositable
    ///         - Depositable keys count should respect targetLimit value
    /// @param nodeOperatorId ID of the Node Operator
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external;

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

    /// @notice Report Node Operator's key as slashed.
    /// @notice Called by `Verifier` contract. See `Verifier.processSlashedProof`.
    /// @param nodeOperatorId The ID of the Node Operator
    /// @param keyIndex The index of the validator key that was slashed
    function onValidatorSlashed(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external;

    /// @notice Report Node Operator's keys as withdrawn and charge penalties associated with exit if any.
    ///         A validator is considered withdrawn in the following cases:
    ///         - if it's an exit of a non-slashed validator, when a withdrawal of the validator is included in a beacon
    ///           block;
    ///         - if it's an exit of a slashed validator, when the committee reports such a validator as withdrawn; note
    ///           that it can happen earlier than the actual withdrawal is included on the beacon chain if the committee
    ///           decides it can account for all penalties in advance;
    ///         - if it's a consolidated validator, when the corresponding pending consolidation is processed and the
    ///           balance of the validator has been moved to another validator.
    /// @notice Called by `Verifier` contract.
    /// @param validatorInfos An array WithdrawnValidatorInfo structs
    function reportWithdrawnValidators(
        WithdrawnValidatorInfo[] calldata validatorInfos
    ) external;

    /// @notice Checks if a validator was reported as slashed
    /// @param nodeOperatorId The ID of the node operator
    /// @param keyIndex The index of the validator key
    /// @return bool True if a validator was reported as slashed
    function isValidatorSlashed(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) external view returns (bool);

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
