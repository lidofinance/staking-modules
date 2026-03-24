// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";

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
interface IBaseModule is IStakingModule, IAccessControlEnumerable, IAssetRecovererLib {
    event NodeOperatorAdded(
        uint256 indexed nodeOperatorId,
        address indexed managerAddress,
        address indexed rewardAddress,
        bool extendedManagerPermissions
    );
    event ReferrerSet(uint256 indexed nodeOperatorId, address indexed referrer);
    event DepositableSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 depositableKeysCount);
    event VettedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 vettedKeysCount);
    event VettedSigningKeysCountDecreased(uint256 indexed nodeOperatorId);
    event DepositedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 depositedKeysCount);
    event ExitedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 exitedKeysCount);
    event TotalSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 totalKeysCount);
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
    event NodeOperatorBalanceUpdated(uint256 indexed operatorId, uint256 balanceWei);
    event ValidatorSlashingReported(uint256 indexed nodeOperatorId, uint256 keyIndex, bytes pubkey);
    event KeyAllocatedBalanceChanged(uint256 indexed nodeOperatorId, uint256 indexed keyIndex, uint256 newTotal);
    event KeyConfirmedBalanceChanged(uint256 indexed nodeOperatorId, uint256 indexed keyIndex, uint256 newBalance);
    event KeyRemovalChargeApplied(uint256 indexed nodeOperatorId);

    event GeneralDelayedPenaltyReported(
        uint256 indexed nodeOperatorId,
        bytes32 indexed penaltyType,
        uint256 amount,
        uint256 additionalFine,
        string details
    );
    event GeneralDelayedPenaltyCancelled(uint256 indexed nodeOperatorId, uint256 amount);
    event GeneralDelayedPenaltyCompensated(uint256 indexed nodeOperatorId, uint256 amount);
    event GeneralDelayedPenaltySettled(uint256 indexed nodeOperatorId, uint256 amount);
    event NodeOperatorDepositInfoFullyUpdated();
    event FullDepositInfoUpdateRequested();

    event NodeOperatorManagerAddressChangeProposed(
        uint256 indexed nodeOperatorId,
        address indexed oldProposedAddress,
        address indexed newProposedAddress
    );
    event NodeOperatorRewardAddressChangeProposed(
        uint256 indexed nodeOperatorId,
        address indexed oldProposedAddress,
        address indexed newProposedAddress
    );
    // args order as in https://github.com/OpenZeppelin/openzeppelin-contracts/blob/11dc5e3809ebe07d5405fe524385cbe4f890a08b/contracts/access/Ownable.sol#L33
    event NodeOperatorManagerAddressChanged(
        uint256 indexed nodeOperatorId,
        address indexed oldAddress,
        address indexed newAddress
    );
    // args order as in https://github.com/OpenZeppelin/openzeppelin-contracts/blob/11dc5e3809ebe07d5405fe524385cbe4f890a08b/contracts/access/Ownable.sol#L33
    event NodeOperatorRewardAddressChanged(
        uint256 indexed nodeOperatorId,
        address indexed oldAddress,
        address indexed newAddress
    );

    error CannotAddKeys();
    error NodeOperatorDoesNotExist();
    error SenderIsNotEligible();
    error InvalidVetKeysPointer();
    error ZeroExitBalance();
    error SlashingPenaltyIsNotApplicable();
    error ValidatorSlashingAlreadyReported();
    error InvalidWithdrawnValidatorInfo();

    error PubkeyMismatch();
    error InvalidAmount();
    error InvalidInput();
    error NotEnoughKeys();

    error KeysLimitExceeded();
    error SigningKeysInvalidOffset();
    error DepositableKeysWithUnsupportedWithdrawalCredentials();

    error ZeroLocatorAddress();
    error ZeroAccountingAddress();
    error ZeroExitPenaltiesAddress();
    error ZeroAdminAddress();
    error ZeroSenderAddress();
    error ZeroParametersRegistryAddress();
    error ZeroModuleType();
    error ZeroPenaltyType();
    error DepositInfoIsNotUpToDate();
    error UnreportableBalance();

    error InvalidManagerAddress();
    error InvalidRewardAddress();

    error AlreadyProposed();
    error SameAddress();
    error SenderIsNotManagerAddress();
    error SenderIsNotRewardAddress();
    error SenderIsNotProposedAddress();
    error MethodCallIsNotAllowed();
    error ZeroManagerAddress();
    error ZeroRewardAddress();

    function STAKING_ROUTER_ROLE() external view returns (bytes32);

    function REPORT_GENERAL_DELAYED_PENALTY_ROLE() external view returns (bytes32);

    function SETTLE_GENERAL_DELAYED_PENALTY_ROLE() external view returns (bytes32);

    function VERIFIER_ROLE() external view returns (bytes32);

    function REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE() external view returns (bytes32);

    function REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE() external view returns (bytes32);

    function CREATE_NODE_OPERATOR_ROLE() external view returns (bytes32);

    function LIDO_LOCATOR() external view returns (ILidoLocator);

    function STETH() external view returns (IStETH);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function ACCOUNTING() external view returns (IAccounting);

    function EXIT_PENALTIES() external view returns (IExitPenalties);

    function FEE_DISTRIBUTOR() external view returns (address);

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
    /// @notice Increases locked bond by `amount + additionalFine` for this report
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

    /// @notice Compensate general delayed penalty (locked bond) for the given Node Operator from Node Operator's bond
    /// @dev Can only be called by the Node Operator manager
    /// @param nodeOperatorId ID of the Node Operator
    function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external;

    /// @notice Cancel previously reported and not settled general delayed penalty for the given Node Operator
    /// @notice The funds will be unlocked
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount of penalty to cancel
    function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount) external;

    /// @notice Settles locked bond for eligible Node Operators
    /// @dev SETTLE_GENERAL_DELAYED_PENALTY_ROLE role is expected to be assigned to Easy Track
    /// @param nodeOperatorIds IDs of the Node Operators
    /// @param maxAmounts Maximum amounts to settle for each Node Operator
    function settleGeneralDelayedPenalty(uint256[] memory nodeOperatorIds, uint256[] memory maxAmounts) external;

    /// @notice Propose a new manager address for the Node Operator.
    /// @dev Passing address(0) clears the pending proposal without changing the current manager address.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed manager address, or address(0) to cancel the current proposal
    function proposeNodeOperatorManagerAddressChange(uint256 nodeOperatorId, address proposedAddress) external;

    /// @notice Confirm a new manager address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorManagerAddressChange(uint256 nodeOperatorId) external;

    /// @notice Reset the manager address to the reward address.
    ///         Should be called from the reward address
    /// @param nodeOperatorId ID of the Node Operator
    function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external;

    /// @notice Propose a new reward address for the Node Operator.
    /// @dev Passing address(0) clears the pending proposal without changing the current reward address.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param proposedAddress Proposed reward address, or address(0) to cancel the current proposal
    function proposeNodeOperatorRewardAddressChange(uint256 nodeOperatorId, address proposedAddress) external;

    /// @notice Confirm a new reward address for the Node Operator.
    ///         Should be called from the currently proposed address
    /// @param nodeOperatorId ID of the Node Operator
    function confirmNodeOperatorRewardAddressChange(uint256 nodeOperatorId) external;

    /// @notice Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newAddress Proposed reward address
    function changeNodeOperatorRewardAddress(uint256 nodeOperatorId, address newAddress) external;

    /// @notice Update depositable validators data for the given Node Operator.
    /// @dev The following rules are applied:
    ///         - Unbonded keys can not be depositable
    ///         - Unvetted keys can not be depositable
    ///         - Depositable keys count should respect targetLimit value
    /// @param nodeOperatorId ID of the Node Operator
    function updateDepositableValidatorsCount(uint256 nodeOperatorId) external;

    /// @notice Update deposit info for the given Node Operator.
    /// @param nodeOperatorId ID of the Node Operator
    function updateDepositInfo(uint256 nodeOperatorId) external;

    /// @notice Request a full update of deposit info for all node operators.
    ///         Should be called after external changes that can affect deposit info such as bond curve change or parameters update.
    function requestFullDepositInfoUpdate() external;

    /// @notice Request a batch update of deposit info for node operators.
    ///         If `requestFullDepositInfoUpdate` was called before, the update will start from the first operator.
    ///         Otherwise, it will continue from the next operator after the last updated one.
    /// @param maxCount Maximum number of operators to update in this batch
    /// @return operatorsLeft Number of operators left to update
    function batchDepositInfoUpdate(uint256 maxCount) external returns (uint256 operatorsLeft);

    /// @notice Get the number of Node Operators with outdated deposit info that requires update.
    function getNodeOperatorDepositInfoToUpdateCount() external view returns (uint256 count);

    /// @notice Get Node Operator info
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator info
    function getNodeOperator(uint256 nodeOperatorId) external view returns (NodeOperator memory);

    /// @notice Get Node Operator management properties
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator management properties
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory);

    /// @notice Get Node Operator owner. Owner is manager address if `extendedManagerPermissions` is enabled and reward address otherwise
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Node Operator owner
    function getNodeOperatorOwner(uint256 nodeOperatorId) external view returns (address);

    /// @notice Get Node Operator non-withdrawn keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Non-withdrawn keys count
    function getNodeOperatorNonWithdrawnKeys(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Returns tracked operator balance (active validator base stake plus tracked extra).
    /// @dev The tracked extra is intentionally monotonic for active validators and is reduced on withdrawal reporting,
    ///      not on intermediate balance decreases, so the value serves both top-up allocation and withdrawal penalty accounting.
    /// @param nodeOperatorId ID of the Node Operator
    function getNodeOperatorBalance(uint256 nodeOperatorId) external view returns (uint256);

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
    /// @param keyIndex Index of the key in the Node Operator's keys storage
    function reportValidatorSlashing(uint256 nodeOperatorId, uint256 keyIndex) external;

    /// @notice Update verified on-chain balance for a key.
    /// @dev The function stores balance relative to MIN_ACTIVATION_BALANCE.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndex Index of the key in the Node Operator's keys storage
    /// @param currentBalanceWei Proven current validator balance in wei
    function reportValidatorBalance(uint256 nodeOperatorId, uint256 keyIndex, uint256 currentBalanceWei) external;

    /// @notice Get cumulative top-up amounts allocated to Node Operator keys (above MIN_ACTIVATION_BALANCE)
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Count of keys to get
    /// @return balances Allocated balances above MIN_ACTIVATION_BALANCE (wei)
    function getKeyAllocatedBalances(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances);

    /// @notice Get verifier-confirmed balances for Node Operator keys (above MIN_ACTIVATION_BALANCE)
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Count of keys to get
    /// @return balances Confirmed balances above MIN_ACTIVATION_BALANCE (wei)
    function getKeyConfirmedBalances(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances);

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
    /// @param validatorInfos An array of WithdrawnValidatorInfo structs
    function reportRegularWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external;

    /// @notice Report withdrawn validators that have been slashed.
    /// @notice Called by the Easy Track EVM script executor via a motion started by the dedicated committee.
    /// @param validatorInfos An array of WithdrawnValidatorInfo structs
    function reportSlashedWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external;

    /// @notice Checks if a validator was reported as slashed
    /// @param nodeOperatorId The ID of the node operator
    /// @param keyIndex Index of the key in the Node Operator's keys storage
    /// @return bool True if a validator was reported as slashed
    function isValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool);

    /// @notice Check if the given Node Operator's key is reported as withdrawn
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndex Index of the key in the Node Operator's keys storage
    /// @return Is validator reported as withdrawn or not
    function isValidatorWithdrawn(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool);

    /// @notice Remove keys for the Node Operator. Charging is module-specific (e.g., CSM applies a per-key fee).
    ///         This method is a part of the Optimistic Vetting scheme. After key deletion `totalVettedKeys`
    ///         is set equal to `totalAddedKeys`. If invalid keys are not removed, the unvetting process will be repeated
    ///         and `decreaseVettedSigningKeysCount` will be called by StakingRouter.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startIndex Index of the first key
    /// @param keysCount Keys count to delete
    function removeKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) external;
}
