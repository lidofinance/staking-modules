// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";
import { IERC20LockVaultFactory } from "./IERC20LockVaultFactory.sol";

/// @notice Operator-level ERC20 lock registry and weight boost provider.
interface IERC20LockBoostProvider is IWeightBoostProvider {
    struct LockBoostStep {
        uint128 minAmount;
        uint32 multiplierBP;
    }

    struct LockInfo {
        address vault;
        uint128 amount;
        uint128 lockUntil;
    }

    event TokensLocked(uint256 indexed nodeOperatorId, uint256 amount, uint256 lockUntil);
    event TokensWithdrawn(
        uint256 indexed nodeOperatorId,
        address indexed receiver,
        uint256 amount,
        uint256 remainingAmount
    );
    event VaultCreated(uint256 indexed nodeOperatorId, address indexed vault, address indexed token);
    event LockPeriodSet(uint256 lockPeriod);
    event LockBoostStepsSet(LockBoostStep[] steps);

    error ZeroAddress();
    error ZeroAdminAddress();
    error InvalidAmount();
    error InvalidLockPeriod();
    error InvalidLockBoostSteps();
    error SameLockPeriod();
    error NodeOperatorDoesNotExist();
    error SenderIsNotNodeOperatorOwner();
    error NoTokensLocked();
    error LockPeriodNotEnded();

    /// @notice ERC20 token address.
    function TOKEN() external view returns (address);

    /// @notice Factory creating per-operator ERC20 lock vaults.
    function VAULT_FACTORY() external view returns (IERC20LockVaultFactory);

    /// @notice Minimum lock period allowed by the registry.
    function MIN_LOCK_PERIOD() external view returns (uint256);

    /// @notice Maximum lock period allowed by the registry.
    function MAX_LOCK_PERIOD() external view returns (uint256);

    /// @notice Role allowed to set the default lock period.
    function SET_LOCK_PERIOD_ROLE() external view returns (bytes32);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param lockPeriod Initial token lock period.
    function initialize(address admin, uint256 lockPeriod) external;

    /// @notice Returns the initialized version of the contract.
    function getInitializedVersion() external view returns (uint64);

    /// @notice Returns the current lock period.
    function getLockPeriod() external view returns (uint256);

    /// @notice Set the default lock period applied to new locks and top-ups.
    /// @param lockPeriod New lock period.
    function setLockPeriod(uint256 lockPeriod) external;

    /// @notice Set token lock weight multiplier steps.
    /// @param steps Ordered lock amount thresholds with full multiplier in basis points.
    /// @dev Each step applies from minAmount inclusive until the next step minAmount.
    ///      10_000 means no scaling, values below 10_000 penalize the weight.
    ///      Existing weights are not refreshed by this call;
    ///      a full deposit info update is requested via MetaRegistry.
    ///      Disable the boost provider in MetaRegistry to turn off the configured boosts.
    function setLockBoostSteps(LockBoostStep[] calldata steps) external;

    /// @notice Returns token lock boost steps.
    /// @return steps Stored lock boost steps.
    function getLockBoostSteps() external view returns (LockBoostStep[] memory steps);

    /// @notice Lock tokens for a Node Operator or add tokens to an existing lock.
    /// @param nodeOperatorId Node Operator ID.
    /// @param amount Token amount to lock.
    /// @dev Each call resets the lock period.
    function lock(uint256 nodeOperatorId, uint256 amount) external;

    /// @notice Withdraw tokens after the lock period or when early withdrawal is allowed.
    /// @param nodeOperatorId Node Operator ID.
    /// @param amount Token amount to withdraw.
    /// @param receiver Address to receive tokens.
    function withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) external;

    /// @notice Get Node Operator lock info.
    /// @param nodeOperatorId Node Operator ID.
    /// @return lockInfo Stored lock info.
    function getNodeOperatorLock(uint256 nodeOperatorId) external view returns (LockInfo memory lockInfo);

    /// @notice Get Node Operator vault address.
    /// @param nodeOperatorId Node Operator ID.
    /// @return vault Stored vault address or zero if no vault has been created yet.
    function getVault(uint256 nodeOperatorId) external view returns (address vault);
}
