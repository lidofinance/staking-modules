// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @notice Operator-level ERC20 lock registry and weight boost provider. In this provider,
///         `Step.threshold` is the locked token amount and `Step.value` is the weight multiplier increment above MAX_BP.
interface IERC20LockBoostProvider is IStepwiseWeightBoost {
    /// @dev Lock state of a Node Operator. `vault` is zero until the first lock creates it; `lockUntil`
    ///      restarts on every lock and is zeroed once the lock is fully withdrawn.
    struct OperatorLock {
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

    error ZeroTokenAddress();
    error ZeroVaultBeaconAddress();
    error InvalidAmount();
    error InvalidLockPeriod();
    error SameLockPeriod();
    error NoTokensLocked();
    error LockPeriodNotEnded();

    /// @notice ERC20 token address.
    function TOKEN() external view returns (address);

    /// @notice Beacon used by per-operator ERC20 lock vault proxies.
    function VAULT_BEACON() external view returns (IBeacon);

    /// @notice Minimum lock period allowed by the provider.
    function MIN_LOCK_PERIOD() external view returns (uint256);

    /// @notice Maximum lock period allowed by the provider.
    function MAX_LOCK_PERIOD() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param lockPeriod Initial token lock period.
    /// @param steps Initial steps. Thresholds must be nonzero; values must not exceed MAX_STEP_VALUE.
    function initialize(address admin, uint256 lockPeriod, Step[] calldata steps) external;

    /// @notice Returns the current lock period.
    function getLockPeriod() external view returns (uint256);

    /// @notice Set the default lock period applied to new locks and top-ups. Only DEFAULT_ADMIN_ROLE;
    ///         existing locks keep their deadlines.
    /// @param lockPeriod New lock period, in [MIN_LOCK_PERIOD, MAX_LOCK_PERIOD].
    function setLockPeriod(uint256 lockPeriod) external;

    /// @notice Lock tokens for a Node Operator or add tokens to an existing lock. Only the Node
    ///         Operator owner.
    /// @dev Each call restarts the lock period for the whole locked amount.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param amount Token amount to lock.
    function lock(uint256 nodeOperatorId, uint256 amount) external;

    /// @notice Withdraw locked tokens. Only the Node Operator owner. Allowed after the lock period, or
    ///         early when the operator is outside any group and has neither active nor depositable
    ///         validators.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param amount Token amount to withdraw.
    /// @param receiver Address to receive tokens.
    function withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) external;

    /// @notice Returns the Node Operator lock state.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return operatorLock Stored lock state.
    function getLock(uint256 nodeOperatorId) external view returns (OperatorLock memory operatorLock);

    /// @notice Returns the Node Operator vault address.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return vault Stored vault address or zero if no vault has been created yet.
    function getVault(uint256 nodeOperatorId) external view returns (address vault);
}
