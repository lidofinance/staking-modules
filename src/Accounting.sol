// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BondCore } from "./abstract/BondCore.sol";
import { BondCurve } from "./abstract/BondCurve.sol";
import { BondLock } from "./abstract/BondLock.sol";
import { FeeSplits } from "./abstract/FeeSplits.sol";
import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";
import { PausableWithRoles } from "./abstract/PausableWithRoles.sol";

import { AssetRecovererLib } from "./lib/AssetRecovererLib.sol";

import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IFeeDistributor } from "./interfaces/IFeeDistributor.sol";
import { IERC20Permit } from "./interfaces/IERC20Permit.sol";

/// @author vgorkavenko
/// @notice This contract stores the Node Operators' bonds in the form of stETH shares,
///         so it should be considered in the recovery process
contract Accounting is
    IAccounting,
    BondCore,
    BondCurve,
    BondLock,
    FeeSplits,
    PausableWithRoles,
    AccessControlEnumerableUpgradeable,
    AssetRecoverer
{
    uint64 internal constant INITIALIZED_VERSION = 3;

    bytes32 public constant MANAGE_BOND_CURVES_ROLE = keccak256("MANAGE_BOND_CURVES_ROLE");
    bytes32 public constant SET_BOND_CURVE_ROLE = keccak256("SET_BOND_CURVE_ROLE");
    IBaseModule public immutable MODULE;
    IFeeDistributor public immutable FEE_DISTRIBUTOR;

    mapping(uint256 nodeOperatorId => address rewardsClaimer) internal _rewardsClaimers;
    address public chargePenaltyRecipient;

    modifier onlyModule() {
        _onlyModule();
        _;
    }

    /// @param lidoLocator Lido Locator contract address
    /// @param module Staking Module contract address
    /// @param feeDistributor Fee Distributor contract address
    /// @param minBondLockPeriod Min time in seconds for the bondLock period
    /// @param maxBondLockPeriod Max time in seconds for the bondLock period
    constructor(
        address lidoLocator,
        address module,
        address feeDistributor,
        uint256 minBondLockPeriod,
        uint256 maxBondLockPeriod
    ) BondCore(lidoLocator) BondLock(minBondLockPeriod, maxBondLockPeriod) {
        if (module == address(0)) revert ZeroModuleAddress();
        if (feeDistributor == address(0)) revert ZeroFeeDistributorAddress();

        MODULE = IBaseModule(module);
        FEE_DISTRIBUTOR = IFeeDistributor(feeDistributor);

        _disableInitializers();
    }

    /// @dev Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
    ///      It is recommended to call this method in the same transaction as the deployment transaction
    ///      and perform extensive deployment verification before using the contract instance.
    /// @param bondCurve Initial bond curve
    /// @param admin Admin role member address
    /// @param bondLockPeriod Bond lock period in seconds
    /// @param _chargePenaltyRecipient Recipient of the charge penalty type
    function initialize(
        BondCurveIntervalInput[] calldata bondCurve,
        address admin,
        uint256 bondLockPeriod,
        address _chargePenaltyRecipient
    ) external reinitializer(INITIALIZED_VERSION) {
        __BondCurve_init(bondCurve);
        __BondLock_init(bondLockPeriod);

        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _setChargePenaltyRecipient(_chargePenaltyRecipient);

        LIDO.approve(address(WSTETH), type(uint256).max);
        LIDO.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
        LIDO.approve(address(BURNER), type(uint256).max);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
    ///      If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
    ///      To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.
    // solhint-disable-next-line no-empty-blocks
    function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION) {}

    /// @inheritdoc IAccounting
    function setChargePenaltyRecipient(address _chargePenaltyRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setChargePenaltyRecipient(_chargePenaltyRecipient);
    }

    /// @inheritdoc IAccounting
    function setBondLockPeriod(uint256 period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BondLock._setBondLockPeriod(period);
    }

    /// @inheritdoc IAccounting
    function updateFeeSplits(
        uint256 nodeOperatorId,
        FeeSplit[] calldata feeSplits,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external {
        _onlyNodeOperatorOwner(nodeOperatorId);
        if (
            FeeSplits.hasSplits(nodeOperatorId) &&
            FEE_DISTRIBUTOR.getFeesToDistribute(nodeOperatorId, cumulativeFeeShares, rewardsProof) != 0
        ) {
            revert FeeSplitsChangeWithUndistributedRewards();
        }
        FeeSplits._updateFeeSplits(nodeOperatorId, feeSplits, address(LIDO));
    }

    /// @inheritdoc IAccounting
    function addBondCurve(
        BondCurveIntervalInput[] calldata bondCurve
    ) external onlyRole(MANAGE_BOND_CURVES_ROLE) returns (uint256 id) {
        id = BondCurve._addBondCurve(bondCurve);
    }

    /// @inheritdoc IAccounting
    function updateBondCurve(
        uint256 curveId,
        BondCurveIntervalInput[] calldata bondCurve
    ) external onlyRole(MANAGE_BOND_CURVES_ROLE) {
        BondCurve._updateBondCurve(curveId, bondCurve);
        MODULE.requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IAccounting
    function setBondCurve(uint256 nodeOperatorId, uint256 curveId) external onlyRole(SET_BOND_CURVE_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        BondCurve._setBondCurve(nodeOperatorId, curveId);
        MODULE.updateDepositInfo(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function depositETH(address from, uint256 nodeOperatorId) external payable whenResumed onlyModule {
        BondCore._depositETH(from, nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function depositETH(uint256 nodeOperatorId) external payable whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        BondCore._depositETH(msg.sender, nodeOperatorId);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function depositStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external whenResumed onlyModule {
        _unwrapPermitIfRequired(address(LIDO), from, permit);
        BondCore._depositStETH(from, nodeOperatorId, stETHAmount);
    }

    /// @inheritdoc IAccounting
    function depositStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        _unwrapPermitIfRequired(address(LIDO), msg.sender, permit);
        BondCore._depositStETH(msg.sender, nodeOperatorId, stETHAmount);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function depositWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external whenResumed onlyModule {
        _unwrapPermitIfRequired(address(WSTETH), from, permit);
        BondCore._depositWstETH(from, nodeOperatorId, wstETHAmount);
    }

    /// @inheritdoc IAccounting
    function depositWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        _unwrapPermitIfRequired(address(WSTETH), msg.sender, permit);
        BondCore._depositWstETH(msg.sender, nodeOperatorId, wstETHAmount);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function claimRewardsStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 claimedShares) {
        NodeOperatorManagementProperties memory no = _checkAndGetEligibleNodeOperatorProperties(nodeOperatorId);

        uint256 claimableShares = _pullAndSplitFeeRewards(nodeOperatorId, cumulativeFeeShares, rewardsProof);
        if (stETHAmount != 0 && claimableShares != 0) {
            claimedShares = BondCore._claimStETH(nodeOperatorId, stETHAmount, claimableShares, no.rewardAddress);
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function claimRewardsWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 claimedWstETH) {
        NodeOperatorManagementProperties memory no = _checkAndGetEligibleNodeOperatorProperties(nodeOperatorId);

        uint256 claimableShares = _pullAndSplitFeeRewards(nodeOperatorId, cumulativeFeeShares, rewardsProof);
        if (wstETHAmount != 0 && claimableShares != 0) {
            claimedWstETH = BondCore._claimWstETH(nodeOperatorId, wstETHAmount, claimableShares, no.rewardAddress);
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function claimRewardsUnstETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 requestId) {
        NodeOperatorManagementProperties memory no = _checkAndGetEligibleNodeOperatorProperties(nodeOperatorId);

        uint256 claimableShares = _pullAndSplitFeeRewards(nodeOperatorId, cumulativeFeeShares, rewardsProof);
        if (stETHAmount != 0 && claimableShares != 0) {
            requestId = BondCore._claimUnstETH(nodeOperatorId, stETHAmount, claimableShares, no.rewardAddress);
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function lockBond(uint256 nodeOperatorId, uint256 amount) external onlyModule {
        BondLock._lock(nodeOperatorId, amount);
    }

    /// @inheritdoc IAccounting
    function releaseLockedBond(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool released) {
        uint256 lockedAmount = BondLock.getLockedBond(nodeOperatorId);
        if (lockedAmount == 0) return released;

        if (BondLock.isLockExpired(nodeOperatorId)) {
            unlockExpiredLock(nodeOperatorId);
            return released;
        }
        BondLock._unlock(nodeOperatorId, amount);
        released = true;
    }

    /// @inheritdoc IAccounting
    function unlockExpiredLock(uint256 nodeOperatorId) public {
        BondLock._unlockExpiredLock(nodeOperatorId);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function compensateLockedBond(uint256 nodeOperatorId) external onlyModule returns (uint256 compensatedAmount) {
        uint256 lockedAmount = BondLock.getLockedBond(nodeOperatorId);
        if (lockedAmount == 0) return 0;

        if (BondLock.isLockExpired(nodeOperatorId)) {
            unlockExpiredLock(nodeOperatorId);
            return 0;
        }

        (uint256 currentBond, uint256 requiredBond) = getBondSummary(nodeOperatorId);
        // `requiredBond` already includes `lockedAmount`
        uint256 requiredBondWithoutLock = requiredBond - lockedAmount;
        if (currentBond <= requiredBondWithoutLock) return 0;

        unchecked {
            uint256 maxCompensatableAmount = currentBond - requiredBondWithoutLock;
            compensatedAmount = lockedAmount < maxCompensatableAmount ? lockedAmount : maxCompensatableAmount;
        }
        BondCore._burn(nodeOperatorId, compensatedAmount);
        BondLock._unlock(nodeOperatorId, compensatedAmount);
        emit BondLockCompensated(nodeOperatorId, compensatedAmount);
    }

    /// @inheritdoc IAccounting
    function settleLockedBond(
        uint256 nodeOperatorId,
        uint256 maxAmount
    ) external onlyModule returns (uint256 amountSettled) {
        uint256 lockedAmount = BondLock.getLockedBond(nodeOperatorId);
        if (lockedAmount == 0) return amountSettled;

        if (BondLock.isLockExpired(nodeOperatorId)) {
            unlockExpiredLock(nodeOperatorId);
            return amountSettled;
        }
        amountSettled = lockedAmount < maxAmount ? lockedAmount : maxAmount;
        if (amountSettled > 0) {
            BondCore._burn(nodeOperatorId, amountSettled);
            // unlock all amountSettled even if bond isn't covered lock fully since debt will be created in this case
            BondLock._unlock(nodeOperatorId, amountSettled);
        }
    }

    /// @inheritdoc IAccounting
    function penalize(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool penaltyCovered) {
        uint256 notBurnedAmount = BondCore._burn(nodeOperatorId, amount);
        penaltyCovered = notBurnedAmount == 0;
    }

    /// @inheritdoc IAccounting
    function chargeFee(uint256 nodeOperatorId, uint256 amount) external onlyModule returns (bool) {
        return BondCore._charge(nodeOperatorId, amount, chargePenaltyRecipient);
    }

    /// @inheritdoc IAccounting
    function pullAndSplitFeeRewards(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external {
        _onlyExistingNodeOperator(nodeOperatorId);
        _pullAndSplitFeeRewards(nodeOperatorId, cumulativeFeeShares, rewardsProof);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function setCustomRewardsClaimer(uint256 nodeOperatorId, address rewardsClaimer) external {
        _onlyNodeOperatorOwner(nodeOperatorId);
        if (rewardsClaimer == _rewardsClaimers[nodeOperatorId]) revert SameAddress();
        _rewardsClaimers[nodeOperatorId] = rewardsClaimer;
        emit CustomRewardsClaimerSet(nodeOperatorId, rewardsClaimer);
    }

    /// @inheritdoc AssetRecoverer
    function recoverERC20(address token, uint256 amount) external override {
        _onlyRecoverer();
        if (token == address(LIDO)) revert NotAllowedToRecover();
        AssetRecovererLib.recoverERC20(token, amount);
    }

    /// @notice Recover all stETH shares from the contract
    /// @dev Accounts for the bond funds stored during recovery
    function recoverStETHShares() external {
        _onlyRecoverer();
        uint256 shares = LIDO.sharesOf(address(this)) - totalBondShares();
        AssetRecovererLib.recoverStETHShares(address(LIDO), shares);
    }

    /// @inheritdoc IAccounting
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IAccounting
    function getCustomRewardsClaimer(uint256 nodeOperatorId) external view returns (address) {
        return _rewardsClaimers[nodeOperatorId];
    }

    /// @inheritdoc IAccounting
    function getUnbondedKeysCount(uint256 nodeOperatorId) external view returns (uint256) {
        return _getUnbondedKeysCount({ nodeOperatorId: nodeOperatorId, includeLockedBond: true });
    }

    /// @inheritdoc IAccounting
    function getUnbondedKeysCountToEject(uint256 nodeOperatorId) external view returns (uint256) {
        return _getUnbondedKeysCount({ nodeOperatorId: nodeOperatorId, includeLockedBond: false });
    }

    /// @inheritdoc IAccounting
    function getBondAmountByKeysCountWstETH(uint256 keysCount, uint256 curveId) external view returns (uint256) {
        return _sharesByEth(BondCurve.getBondAmountByKeysCount(keysCount, curveId));
    }

    /// @inheritdoc IAccounting
    function getRequiredBondForNextKeysWstETH(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) external view returns (uint256) {
        return _sharesByEth(getRequiredBondForNextKeys(nodeOperatorId, additionalKeys));
    }

    /// @inheritdoc IAccounting
    function getClaimableBondShares(uint256 nodeOperatorId) external view returns (uint256) {
        return _getClaimableBondShares(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function getClaimableRewardsAndBondShares(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external view returns (uint256 claimableShares) {
        uint256 feesToDistribute = FEE_DISTRIBUTOR.getFeesToDistribute(
            nodeOperatorId,
            cumulativeFeeShares,
            rewardsProof
        );

        (uint256 current, uint256 required) = getBondSummaryShares(nodeOperatorId);
        current = current + feesToDistribute;

        return Math.saturatingSub(current, required);
    }

    /// @inheritdoc IAccounting
    function getNodeOperatorBondInfo(uint256 nodeOperatorId) external view returns (NodeOperatorBondInfo memory info) {
        info.currentBond = BondCore.getBond(nodeOperatorId);
        info.requiredBond = _getRequiredBond(nodeOperatorId, 0);
        info.lockedBond = BondLock.getLockedBond(nodeOperatorId);
        info.bondDebt = BondCore.getBondDebt(nodeOperatorId);
        info.pendingSharesToSplit = FeeSplits.getPendingSharesToSplit(nodeOperatorId);
    }

    /// @inheritdoc IAccounting
    function getBondSummary(uint256 nodeOperatorId) public view returns (uint256 current, uint256 required) {
        current = BondCore.getBond(nodeOperatorId);
        required = _getRequiredBond(nodeOperatorId, 0);
    }

    /// @inheritdoc IAccounting
    function getBondSummaryShares(uint256 nodeOperatorId) public view returns (uint256 current, uint256 required) {
        current = BondCore.getBondShares(nodeOperatorId);
        required = _getRequiredBondShares(nodeOperatorId, 0);
    }

    /// @inheritdoc IAccounting
    function getRequiredBondForNextKeys(uint256 nodeOperatorId, uint256 additionalKeys) public view returns (uint256) {
        uint256 current = BondCore.getBond(nodeOperatorId);
        uint256 totalRequired = _getRequiredBond(nodeOperatorId, additionalKeys);

        return Math.saturatingSub(totalRequired, current);
    }

    function _pullAndSplitFeeRewards(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) internal returns (uint256 claimableShares) {
        bool hasSplits = FeeSplits.hasSplits(nodeOperatorId);
        if (rewardsProof.length != 0) {
            uint256 distributed = FEE_DISTRIBUTOR.distributeFees(nodeOperatorId, cumulativeFeeShares, rewardsProof);
            if (distributed != 0) {
                BondCore._creditBondShares(nodeOperatorId, distributed);
                // NOTE: All rewards are subject to a split set as of the rewards allocation date.
                //       Any penalties in favour of the protocol should not reduce the amount of the rewards to be split.
                //       Any rewards used to cover protocol penalties should be split later from the new rewards
                //       or the Node Operator bond during claim operations.
                // NOTE: Pending shares are not excluded from the bond balance in `_getUnbondedKeysCount`.
                //       A subsequent rewards distribution will trigger split settlement, so pending shares will be paid out eventually.
                if (hasSplits) FeeSplits._increasePendingSharesToSplit(nodeOperatorId, distributed);
            }
        }
        claimableShares = _getClaimableBondShares(nodeOperatorId);
        if (hasSplits && claimableShares != 0 && !isPaused()) {
            uint256 pendingToSplit = FeeSplits.getPendingSharesToSplit(nodeOperatorId);
            uint256 splittableShares = claimableShares > pendingToSplit ? pendingToSplit : claimableShares;
            SplitTransfer[] memory transfers = FeeSplits.getFeeSplitTransfers(nodeOperatorId, splittableShares);
            uint256 transferredShares;
            for (uint256 i; i < transfers.length; ++i) {
                uint256 shares = transfers[i].shares;
                if (shares != 0) {
                    LIDO.transferShares(transfers[i].recipient, shares);
                    transferredShares += shares;
                }
            }
            // NOTE: `splittableShares` is the whole split operation base. It includes
            //       the Node Operator's retained shares (split remainder), so we
            //       must decrease pending by the base, not by transferred shares sum.
            FeeSplits._decreasePendingSharesToSplit(nodeOperatorId, splittableShares);
            BondCore._unsafeReduceBond(nodeOperatorId, transferredShares);
            // NOTE: It is safe to use unchecked here since `transferredShares` is always <= `claimableShares`
            unchecked {
                claimableShares -= transferredShares;
            }
        }
    }

    function _unwrapPermitIfRequired(address token, address from, PermitInput calldata permit) internal {
        if (permit.value > 0 && IERC20Permit(token).allowance(from, address(this)) < permit.value) {
            IERC20Permit(token).permit({
                owner: from,
                spender: address(this),
                value: permit.value,
                deadline: permit.deadline,
                v: permit.v,
                r: permit.r,
                s: permit.s
            });
        }
    }

    /// @dev Calculates claimable bond shares accounting for locked bond and withdrawn validators.
    ///      Does not subtract pending split transfers, so in rare cases (e.g. paused Accounting, locked or debted bond)
    ///      may overestimate operator-receivable amount.
    ///      Off-chain integrations should account for `getPendingSharesToSplit`.
    function _getClaimableBondShares(uint256 nodeOperatorId) internal view returns (uint256) {
        (uint256 currentShares, uint256 requiredShares) = getBondSummaryShares(nodeOperatorId);
        return Math.saturatingSub(currentShares, requiredShares);
    }

    function _getRequiredBond(uint256 nodeOperatorId, uint256 additionalKeys) internal view returns (uint256) {
        uint256 curveId = BondCurve.getBondCurveId(nodeOperatorId);
        uint256 nonWithdrawnKeys = MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId);
        uint256 requiredBondForKeys = BondCurve.getBondAmountByKeysCount(nonWithdrawnKeys + additionalKeys, curveId);
        uint256 lockedBond = BondLock.getLockedBond(nodeOperatorId);
        uint256 bondDebt = BondCore.getBondDebt(nodeOperatorId);

        return requiredBondForKeys + lockedBond + bondDebt;
    }

    function _getRequiredBondShares(uint256 nodeOperatorId, uint256 additionalKeys) internal view returns (uint256) {
        return _sharesByEth(_getRequiredBond(nodeOperatorId, additionalKeys));
    }

    /// @dev Unbonded stands for the amount of keys not fully covered with bond
    function _getUnbondedKeysCount(uint256 nodeOperatorId, bool includeLockedBond) internal view returns (uint256) {
        uint256 nonWithdrawnKeys = MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId);
        uint256 currentBond = BondCore.getBond(nodeOperatorId);
        uint256 bondDebt = BondCore.getBondDebt(nodeOperatorId);
        if (bondDebt > currentBond) return nonWithdrawnKeys;
        unchecked {
            currentBond -= bondDebt;
        }

        // Optionally account for locked bond depending on the flag
        if (includeLockedBond) {
            uint256 lockedBond = BondLock.getLockedBond(nodeOperatorId);
            // We use strict condition here since in rare case of equality the outcome of the function will not change
            if (lockedBond > currentBond) return nonWithdrawnKeys;
            unchecked {
                currentBond -= lockedBond;
            }
        }
        // 10 wei is added to account for possible stETH rounding errors
        // https://github.com/lidofinance/lido-dao/issues/442#issuecomment-1182264205.
        // Should be sufficient for ~ 40 years
        uint256 bondedKeys = BondCurve.getKeysCountByBondAmount(
            currentBond + 10 wei,
            BondCurve.getBondCurveId(nodeOperatorId)
        );
        return Math.saturatingSub(nonWithdrawnKeys, bondedKeys);
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId < IStakingModule(address(MODULE)).getNodeOperatorsCount()) return;

        revert NodeOperatorDoesNotExist();
    }

    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        if (MODULE.getNodeOperatorOwner(nodeOperatorId) != msg.sender) revert SenderIsNotEligible();
    }

    function _onlyModule() internal view {
        if (msg.sender != address(MODULE)) revert SenderIsNotModule();
    }

    function _checkAndGetEligibleNodeOperatorProperties(
        uint256 nodeOperatorId
    ) internal view returns (NodeOperatorManagementProperties memory no) {
        no = MODULE.getNodeOperatorManagementProperties(nodeOperatorId);
        if (no.managerAddress == address(0)) revert NodeOperatorDoesNotExist();
        if (no.managerAddress != msg.sender && no.rewardAddress != msg.sender) {
            if (_rewardsClaimers[nodeOperatorId] != msg.sender) revert SenderIsNotEligible();
        }
    }

    function _setChargePenaltyRecipient(address _chargePenaltyRecipient) private {
        if (_chargePenaltyRecipient == address(0)) revert ZeroChargePenaltyRecipientAddress();
        chargePenaltyRecipient = _chargePenaltyRecipient;
        emit ChargePenaltyRecipientSet(_chargePenaltyRecipient);
    }
}
