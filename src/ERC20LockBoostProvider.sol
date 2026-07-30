// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { NodeOperator } from "./interfaces/IBaseModule.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IERC20LockBoostProvider } from "./interfaces/IERC20LockBoostProvider.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP, MAX_WEIGHT_BOOST_BP } from "./lib/Constants.sol";

/// @notice Stores operator-level ERC20 locks and exposes node operator boost for scoring.
contract ERC20LockBoostProvider is Initializable, AccessControlEnumerableUpgradeable, IERC20LockBoostProvider {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct ERC20LockBoostProviderStorage {
        mapping(uint256 nodeOperatorId => LockInfo) locks;
        uint256 lockPeriod;
        LockBoostStep[] lockBoostSteps;
    }

    ICuratedModule public immutable MODULE;
    IMetaRegistry public immutable META_REGISTRY;
    address public immutable TOKEN;
    IBeacon public immutable VAULT_BEACON;
    uint256 public immutable MIN_LOCK_PERIOD;

    bytes32 public constant SET_LOCK_PERIOD_ROLE = keccak256("SET_LOCK_PERIOD_ROLE");
    uint256 public constant MAX_LOCK_PERIOD = 365 days;

    // keccak256(abi.encode(uint256(keccak256("ERC20LockBoostProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_LOCK_BOOST_PROVIDER_STORAGE_LOCATION =
        0x0d048d8a76e474169bd4c83d3eb46f84ff5b8d069b5f5174bf8047b6bd66fb00;

    constructor(address module, address token, address vaultBeacon, uint256 minLockPeriod) {
        if (module == address(0) || token == address(0) || vaultBeacon == address(0)) revert ZeroAddress();
        if (minLockPeriod == 0 || minLockPeriod > MAX_LOCK_PERIOD) revert InvalidLockPeriod();

        ICuratedModule curatedModule = ICuratedModule(module);
        IMetaRegistry metaRegistry = curatedModule.META_REGISTRY();

        MODULE = curatedModule;
        META_REGISTRY = metaRegistry;
        TOKEN = token;
        VAULT_BEACON = IBeacon(vaultBeacon);
        MIN_LOCK_PERIOD = minLockPeriod;

        _disableInitializers();
    }

    /// @inheritdoc IERC20LockBoostProvider
    function initialize(address admin, uint256 lockPeriod) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setLockPeriod(lockPeriod);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function setLockPeriod(uint256 lockPeriod) external onlyRole(SET_LOCK_PERIOD_ROLE) {
        _setLockPeriod(lockPeriod);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function setLockBoostSteps(LockBoostStep[] calldata steps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _checkLockBoostSteps(steps);

        ERC20LockBoostProviderStorage storage $ = _storage();
        delete $.lockBoostSteps;
        uint256 stepsCount = steps.length;
        for (uint256 i; i < stepsCount; ++i) {
            $.lockBoostSteps.push(
                LockBoostStep({ minAmount: steps[i].minAmount, weightBoostBP: steps[i].weightBoostBP })
            );
        }

        emit LockBoostStepsSet(steps);
        META_REGISTRY.notifyWeightBoostProviderConfigChanged();
    }

    /// @inheritdoc IERC20LockBoostProvider
    function lock(uint256 nodeOperatorId, uint256 amount) external {
        _onlyNodeOperatorOwner(nodeOperatorId);
        _lockTokens(nodeOperatorId, amount);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) external {
        _onlyNodeOperatorOwner(nodeOperatorId);

        LockInfo storage lockInfo = _storage().locks[nodeOperatorId];
        if (lockInfo.amount == 0) revert NoTokensLocked();
        if (block.timestamp < lockInfo.lockUntil && !_isEarlyWithdrawalAllowed(nodeOperatorId)) {
            revert LockPeriodNotEnded();
        }

        _withdraw(nodeOperatorId, amount, receiver);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getLockBoostSteps() external view returns (LockBoostStep[] memory steps) {
        steps = _storage().lockBoostSteps;
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = _getMultiplierBP(_storage().locks[nodeOperatorId].amount);
    }

    /// @inheritdoc IERC20LockBoostProvider
    function getNodeOperatorLock(uint256 nodeOperatorId) external view returns (LockInfo memory lockInfo) {
        lockInfo = _storage().locks[nodeOperatorId];
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
        LockInfo storage lockInfo = $.locks[nodeOperatorId];

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
        _syncWeightAfterLockChange(nodeOperatorId, oldAmount, newAmount);
    }

    function _withdraw(uint256 nodeOperatorId, uint256 amount, address receiver) internal {
        if (amount == 0) revert InvalidAmount();

        LockInfo storage lockInfo = _storage().locks[nodeOperatorId];
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
        _syncWeightAfterLockChange(nodeOperatorId, oldAmount, newAmount);
    }

    function _syncWeightAfterLockChange(uint256 nodeOperatorId, uint256 oldAmount, uint256 newAmount) internal {
        uint256 oldMultiplierBP = _getMultiplierBP(oldAmount);
        uint256 newMultiplierBP = _getMultiplierBP(newAmount);
        if (oldMultiplierBP != newMultiplierBP) META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    function _setLockPeriod(uint256 lockPeriod) internal {
        if (lockPeriod < MIN_LOCK_PERIOD || lockPeriod > MAX_LOCK_PERIOD) revert InvalidLockPeriod();
        if (_storage().lockPeriod == lockPeriod) revert SameLockPeriod();

        _storage().lockPeriod = lockPeriod;
        emit LockPeriodSet(lockPeriod);
    }

    function _getMultiplierBP(uint256 amount) internal view returns (uint256 multiplierBP) {
        ERC20LockBoostProviderStorage storage $ = _storage();
        multiplierBP = MAX_BP;
        uint256 stepsCount = $.lockBoostSteps.length;
        for (uint256 i; i < stepsCount; ++i) {
            LockBoostStep storage step = $.lockBoostSteps[i];
            if (amount < step.minAmount) return multiplierBP;
            multiplierBP = MAX_BP + step.weightBoostBP;
        }
    }

    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert SenderIsNotNodeOperatorOwner();
    }

    function _isEarlyWithdrawalAllowed(uint256 nodeOperatorId) internal view returns (bool) {
        if (META_REGISTRY.getNodeOperatorGroupId(nodeOperatorId) != 0) return false;

        NodeOperator memory no = MODULE.getNodeOperator(nodeOperatorId);
        return no.totalDepositedKeys == no.totalWithdrawnKeys && no.depositableValidatorsCount == 0;
    }

    function _checkLockBoostSteps(LockBoostStep[] calldata steps) internal pure {
        uint256 stepsCount = steps.length;
        if (stepsCount == 0) revert InvalidLockBoostSteps();

        if (steps[0].minAmount == 0) revert InvalidLockBoostSteps();
        if (steps[0].weightBoostBP > MAX_WEIGHT_BOOST_BP) revert InvalidLockBoostSteps();

        uint256 previousMinAmount = steps[0].minAmount;
        uint256 previousWeightBoostBP = steps[0].weightBoostBP;

        for (uint256 i = 1; i < stepsCount; ++i) {
            LockBoostStep calldata step = steps[i];
            if (
                step.minAmount <= previousMinAmount ||
                step.weightBoostBP <= previousWeightBoostBP ||
                step.weightBoostBP > MAX_WEIGHT_BOOST_BP
            ) revert InvalidLockBoostSteps();

            previousMinAmount = step.minAmount;
            previousWeightBoostBP = step.weightBoostBP;
        }
    }

    function _storage() internal pure returns (ERC20LockBoostProviderStorage storage $) {
        assembly ("memory-safe") {
            $.slot := ERC20_LOCK_BOOST_PROVIDER_STORAGE_LOCATION
        }
    }
}
