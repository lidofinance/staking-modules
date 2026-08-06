// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";
import { IERC20LockBoostProvider } from "./interfaces/IERC20LockBoostProvider.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Holds operator-level ERC20 locks in per-operator vaults and serves the resulting weight
///         boost to MetaRegistry.
contract ERC20LockBoostProvider is IERC20LockBoostProvider, StepwiseWeightBoost {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct ERC20LockBoostProviderStorage {
        mapping(uint256 nodeOperatorId => OperatorLock) locks;
        uint256 lockPeriod;
    }

    address public immutable TOKEN;
    IBeacon public immutable VAULT_BEACON;
    uint256 public immutable MIN_LOCK_PERIOD;

    uint256 public constant MAX_LOCK_PERIOD = 365 days;

    // keccak256(abi.encode(uint256(keccak256("ERC20LockBoostProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_LOCK_BOOST_PROVIDER_STORAGE_LOCATION =
        0x0d048d8a76e474169bd4c83d3eb46f84ff5b8d069b5f5174bf8047b6bd66fb00;

    constructor(address module, address token, address vaultBeacon, uint256 minLockPeriod) StepwiseWeightBoost(module) {
        if (token == address(0)) revert ZeroTokenAddress();
        if (vaultBeacon == address(0)) revert ZeroVaultBeaconAddress();
        if (minLockPeriod == 0 || minLockPeriod > MAX_LOCK_PERIOD) revert InvalidLockPeriod();

        TOKEN = token;
        VAULT_BEACON = IBeacon(vaultBeacon);
        MIN_LOCK_PERIOD = minLockPeriod;
    }

    /// @inheritdoc IERC20LockBoostProvider
    function initialize(address admin, uint256 lockPeriod, Step[] calldata steps) external initializer {
        _setLockPeriod(lockPeriod);
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function setLockPeriod(uint256 lockPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLockPeriod(lockPeriod);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function lock(uint256 nodeOperatorId, uint256 amount) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);
        _lockTokens(nodeOperatorId, amount);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        OperatorLock storage lockInfo = _storage().locks[nodeOperatorId];
        if (lockInfo.amount == 0) revert NoTokensLocked();
        if (block.timestamp < lockInfo.lockUntil && !_isEarlyWithdrawalAllowed(nodeOperatorId)) {
            revert LockPeriodNotEnded();
        }

        _withdraw(nodeOperatorId, amount, receiver);
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = MAX_BP + StepwiseWeightBoost._stepValueAt(_storage().locks[nodeOperatorId].amount);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getLock(uint256 nodeOperatorId) external view returns (OperatorLock memory operatorLock) {
        operatorLock = _storage().locks[nodeOperatorId];
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getVault(uint256 nodeOperatorId) external view returns (address vault) {
        vault = _storage().locks[nodeOperatorId].vault;
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getLockPeriod() external view returns (uint256) {
        return _storage().lockPeriod;
    }

    function _lockTokens(uint256 nodeOperatorId, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();

        ERC20LockBoostProviderStorage storage $ = _storage();
        OperatorLock storage lockInfo = $.locks[nodeOperatorId];

        address vault = lockInfo.vault;
        if (vault == address(0)) {
            vault = address(
                new BeaconProxy({
                    beacon: address(VAULT_BEACON),
                    data: abi.encodeCall(IERC20LockVault.initialize, (nodeOperatorId))
                })
            );
            lockInfo.vault = vault;
            emit VaultCreated(nodeOperatorId, vault, TOKEN);
        }

        uint256 oldAmount = lockInfo.amount;
        uint256 newAmount = oldAmount + amount;
        uint256 lockUntil = block.timestamp + $.lockPeriod;

        lockInfo.amount = newAmount.toUint128();
        lockInfo.lockUntil = lockUntil.toUint128();

        IERC20(TOKEN).safeTransferFrom(msg.sender, vault, amount);

        emit TokensLocked(nodeOperatorId, amount, lockUntil);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, oldAmount, newAmount);
    }

    function _withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) internal {
        if (amount == 0) revert InvalidAmount();

        OperatorLock storage lockInfo = _storage().locks[nodeOperatorId];
        uint256 oldAmount = lockInfo.amount;
        if (oldAmount == 0) revert NoTokensLocked();
        if (amount > oldAmount) revert InvalidAmount();

        uint256 newAmount = oldAmount - amount;
        lockInfo.amount = newAmount.toUint128();
        if (newAmount == 0) {
            lockInfo.lockUntil = 0;
        }

        IERC20LockVault(lockInfo.vault).transferTokens(receiver, amount);

        emit TokensWithdrawn(nodeOperatorId, receiver, amount, newAmount);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, oldAmount, newAmount);
    }

    function _setLockPeriod(uint256 lockPeriod) internal {
        if (lockPeriod < MIN_LOCK_PERIOD || lockPeriod > MAX_LOCK_PERIOD) revert InvalidLockPeriod();
        if (_storage().lockPeriod == lockPeriod) revert SameLockPeriod();

        _storage().lockPeriod = lockPeriod;
        emit LockPeriodSet(lockPeriod);
    }

    /// @dev The lock only backs allocation weight, so it can be released early once the operator is
    ///      outside any group and has neither active nor depositable validators.
    function _isEarlyWithdrawalAllowed(uint256 nodeOperatorId) internal view returns (bool) {
        if (META_REGISTRY.getNodeOperatorGroupId(nodeOperatorId) != 0) return false;

        NodeOperator memory no = MODULE.getNodeOperator(nodeOperatorId);
        return no.totalDepositedKeys == no.totalWithdrawnKeys && no.depositableValidatorsCount == 0;
    }

    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold != 0;
    }

    function _storage() internal pure returns (ERC20LockBoostProviderStorage storage $) {
        assembly ("memory-safe") {
            $.slot := ERC20_LOCK_BOOST_PROVIDER_STORAGE_LOCATION
        }
    }
}
