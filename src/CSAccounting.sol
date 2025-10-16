// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { CSBondCore } from "./abstract/CSBondCore.sol";
import { CSBondCurve } from "./abstract/CSBondCurve.sol";
import { CSBondLock } from "./abstract/CSBondLock.sol";
import { BondReserve } from "./abstract/BondReserve.sol";
import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { PausableUntil } from "./lib/utils/PausableUntil.sol";
import { AssetRecovererLib } from "./lib/AssetRecovererLib.sol";
import { FeeSplits } from "./lib/FeeSplits.sol";

import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { ICSModule, NodeOperatorManagementProperties } from "./interfaces/ICSModule.sol";
import { ICSAccounting } from "./interfaces/ICSAccounting.sol";
import { IBondReserve } from "./interfaces/IBondReserve.sol";
import { ICSFeeDistributor } from "./interfaces/ICSFeeDistributor.sol";

/// @author vgorkavenko
/// @notice This contract stores the Node Operators' bonds in the form of stETH shares,
///         so it should be considered in the recovery process
contract CSAccounting is
    ICSAccounting,
    CSBondCore,
    CSBondCurve,
    CSBondLock,
    BondReserve,
    PausableUntil,
    AccessControlEnumerableUpgradeable,
    AssetRecoverer
{
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant MANAGE_BOND_CURVES_ROLE =
        keccak256("MANAGE_BOND_CURVES_ROLE");
    bytes32 public constant SET_BOND_CURVE_ROLE =
        keccak256("SET_BOND_CURVE_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");

    ICSModule public immutable MODULE;
    ICSFeeDistributor public immutable FEE_DISTRIBUTOR;
    bool public immutable BOND_RESERVE_IS_ENABLED;
    /// @dev DEPRECATED
    /// @custom:oz-renamed-from feeDistributor
    ICSFeeDistributor internal _feeDistributorOld;
    address public chargePenaltyRecipient;

    mapping(uint256 nodeOperatorId => FeeSplit[]) internal _feeSplits;
    mapping(uint256 nodeOperatorId => uint256 pendingSharesToSplit)
        internal _pendingSharesToSplit;

    modifier onlyModule() {
        if (msg.sender != address(MODULE)) {
            revert SenderIsNotModule();
        }

        _;
    }

    modifier whenBondReserveIsEnabled() {
        if (!BOND_RESERVE_IS_ENABLED) {
            revert BondReserveFeatureDisabled();
        }

        _;
    }

    /// @param lidoLocator Lido locator contract address
    /// @param module Community Staking Module contract address
    /// @param feeDistributor Fee Distributor contract address
    /// @param minBondLockPeriod Min time in seconds for the bondLock period
    /// @param maxBondLockPeriod Max time in seconds for the bondLock period
    /// @param enableBondReserve Whether to enable bond reserve feature
    constructor(
        address lidoLocator,
        address module,
        address feeDistributor,
        uint256 minBondLockPeriod,
        uint256 maxBondLockPeriod,
        bool enableBondReserve
    ) CSBondCore(lidoLocator) CSBondLock(minBondLockPeriod, maxBondLockPeriod) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }
        if (feeDistributor == address(0)) {
            revert ZeroFeeDistributorAddress();
        }

        MODULE = ICSModule(module);
        FEE_DISTRIBUTOR = ICSFeeDistributor(feeDistributor);
        BOND_RESERVE_IS_ENABLED = enableBondReserve;

        _disableInitializers();
    }

    /// @param bondCurve Initial bond curve
    /// @param admin Admin role member address
    /// @param bondLockPeriod Bond lock period in seconds
    /// @param bondReserveMinPeriod Bond reserve minimum period in seconds
    /// @param _chargePenaltyRecipient Recipient of the charge penalty type
    function initialize(
        BondCurveIntervalInput[] calldata bondCurve,
        address admin,
        uint256 bondLockPeriod,
        uint256 bondReserveMinPeriod,
        address _chargePenaltyRecipient
    ) external reinitializer(3) {
        __AccessControlEnumerable_init();
        __CSBondCurve_init(bondCurve);
        __CSBondLock_init(bondLockPeriod);
        __BondReserve_init(bondReserveMinPeriod);

        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _setChargePenaltyRecipient(_chargePenaltyRecipient);

        LIDO.approve(address(WSTETH), type(uint256).max);
        LIDO.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
        LIDO.approve(LIDO_LOCATOR.burner(), type(uint256).max);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
    ///      If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
    function finalizeUpgradeV3(
        uint256 bondReserveMinPeriod
    ) external reinitializer(3) {
        __BondReserve_init(bondReserveMinPeriod);
    }

    /// @inheritdoc ICSAccounting
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc ICSAccounting
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc ICSAccounting
    function setChargePenaltyRecipient(
        address _chargePenaltyRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setChargePenaltyRecipient(_chargePenaltyRecipient);
    }

    /// @inheritdoc ICSAccounting
    function setBondLockPeriod(
        uint256 period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CSBondLock._setBondLockPeriod(period);
    }

    /// @inheritdoc ICSAccounting
    function setBondReserveMinPeriod(
        uint256 period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BondReserve._setBondReserveMinPeriod(period);
    }

    /// @inheritdoc ICSAccounting
    function setFeeSplits(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof,
        FeeSplit[] calldata feeSplits
    ) external {
        _onlyNodeOperatorOwner(nodeOperatorId);
        FeeSplits.setFeeSplits({
            feeSplitsStorage: _feeSplits,
            pendingSharesToSplitStorage: _pendingSharesToSplit,
            feeDistributor: FEE_DISTRIBUTOR,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: cumulativeFeeShares,
            rewardsProof: rewardsProof,
            feeSplits: feeSplits
        });
    }

    /// @inheritdoc ICSAccounting
    function addBondCurve(
        BondCurveIntervalInput[] calldata bondCurve
    ) external onlyRole(MANAGE_BOND_CURVES_ROLE) returns (uint256 id) {
        id = CSBondCurve._addBondCurve(bondCurve);
    }

    /// @inheritdoc ICSAccounting
    function updateBondCurve(
        uint256 curveId,
        BondCurveIntervalInput[] calldata bondCurve
    ) external onlyRole(MANAGE_BOND_CURVES_ROLE) {
        CSBondCurve._updateBondCurve(curveId, bondCurve);
    }

    /// @inheritdoc ICSAccounting
    function setBondCurve(
        uint256 nodeOperatorId,
        uint256 curveId
    ) external onlyRole(SET_BOND_CURVE_ROLE) {
        _onlyExistingNodeOperator(nodeOperatorId);
        CSBondCurve._setBondCurve(nodeOperatorId, curveId);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function depositETH(
        address from,
        uint256 nodeOperatorId
    ) external payable whenResumed onlyModule {
        CSBondCore._depositETH(from, nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function depositETH(uint256 nodeOperatorId) external payable whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        CSBondCore._depositETH(msg.sender, nodeOperatorId);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function depositStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external whenResumed onlyModule {
        _unwrapStETHPermitIfRequired(from, permit);
        CSBondCore._depositStETH(from, nodeOperatorId, stETHAmount);
    }

    /// @inheritdoc ICSAccounting
    function depositStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        _unwrapStETHPermitIfRequired(msg.sender, permit);
        CSBondCore._depositStETH(msg.sender, nodeOperatorId, stETHAmount);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function depositWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external whenResumed onlyModule {
        _unwrapWstETHPermitIfRequired(from, permit);
        CSBondCore._depositWstETH(from, nodeOperatorId, wstETHAmount);
    }

    /// @inheritdoc ICSAccounting
    function depositWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external whenResumed {
        _onlyExistingNodeOperator(nodeOperatorId);
        _unwrapWstETHPermitIfRequired(msg.sender, permit);
        CSBondCore._depositWstETH(msg.sender, nodeOperatorId, wstETHAmount);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function claimRewardsStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 claimedShares) {
        NodeOperatorManagementProperties
            memory no = _checkAndGetEligibleNodeOperatorProperties(
                nodeOperatorId
            );

        uint256 claimableShares = _pullAndSplitFeeRewards(
            nodeOperatorId,
            cumulativeFeeShares,
            rewardsProof
        );
        if (stETHAmount != 0 && claimableShares != 0) {
            claimedShares = CSBondCore._claimStETH(
                nodeOperatorId,
                stETHAmount,
                claimableShares,
                no.rewardAddress
            );
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function claimRewardsWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 claimedWstETH) {
        NodeOperatorManagementProperties
            memory no = _checkAndGetEligibleNodeOperatorProperties(
                nodeOperatorId
            );

        uint256 claimableShares = _pullAndSplitFeeRewards(
            nodeOperatorId,
            cumulativeFeeShares,
            rewardsProof
        );
        if (wstETHAmount != 0 && claimableShares != 0) {
            claimedWstETH = CSBondCore._claimWstETH(
                nodeOperatorId,
                wstETHAmount,
                claimableShares,
                no.rewardAddress
            );
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function claimRewardsUnstETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external whenResumed returns (uint256 requestId) {
        NodeOperatorManagementProperties
            memory no = _checkAndGetEligibleNodeOperatorProperties(
                nodeOperatorId
            );

        uint256 claimableShares = _pullAndSplitFeeRewards(
            nodeOperatorId,
            cumulativeFeeShares,
            rewardsProof
        );
        if (stETHAmount != 0 && claimableShares != 0) {
            requestId = CSBondCore._claimUnstETH(
                nodeOperatorId,
                stETHAmount,
                claimableShares,
                no.rewardAddress
            );
        }
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function increaseBondReserve(
        uint256 nodeOperatorId,
        uint256 newAmount
    ) external whenResumed whenBondReserveIsEnabled {
        _checkAndGetEligibleNodeOperatorProperties(nodeOperatorId);

        if (newAmount == 0) {
            revert InvalidBondReserveAmount();
        }

        (uint256 current, uint256 required) = getBondSummary(nodeOperatorId);
        uint256 reserve = BondReserve.getReservedBond(nodeOperatorId);
        // NOTE: `required` is always >= `reserve` due to fact that `reserve` is a part of `required`
        if (
            reserve >= newAmount || current < (required - reserve) + newAmount
        ) {
            revert InvalidBondReserveAmount();
        }
        BondReserve._setBondReserve(nodeOperatorId, newAmount);
    }

    /// @inheritdoc ICSAccounting
    function removeBondReserve(
        uint256 nodeOperatorId
    ) external whenResumed whenBondReserveIsEnabled {
        // Allow for permissionless call if there are no active and depositable keys. In this case, the bond reserve is useless
        if (MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId) > 0) {
            _checkAndGetEligibleNodeOperatorProperties(nodeOperatorId);
        }

        IBondReserve.BondReserveInfo memory r = BondReserve.getBondReserveInfo(
            nodeOperatorId
        );
        if (r.amount == 0) {
            return;
        }

        if (!_canRemoveBondReserve(nodeOperatorId, r)) {
            revert MinReserveTimeHasNotPassed();
        }
        BondReserve._setBondReserve(nodeOperatorId, 0);
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function lockBondETH(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyModule {
        CSBondLock._lock(nodeOperatorId, amount);
    }

    /// @inheritdoc ICSAccounting
    function releaseLockedBondETH(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyModule {
        CSBondLock._reduceAmount(nodeOperatorId, amount);
    }

    /// @inheritdoc ICSAccounting
    function compensateLockedBondETH(
        uint256 nodeOperatorId
    ) external payable onlyModule {
        (bool success, ) = LIDO_LOCATOR.elRewardsVault().call{
            value: msg.value
        }("");
        if (!success) {
            revert ElRewardsVaultReceiveFailed();
        }

        CSBondLock._reduceAmount(nodeOperatorId, msg.value);
        emit BondLockCompensated(nodeOperatorId, msg.value);
    }

    /// @inheritdoc ICSAccounting
    function settleLockedBondETH(
        uint256 nodeOperatorId
    ) external onlyModule returns (bool applied) {
        applied = false;

        uint256 lockedAmount = CSBondLock.getActualLockedBond(nodeOperatorId);
        if (lockedAmount > 0) {
            uint256 notBurnedAmount = CSBondCore._burn(
                nodeOperatorId,
                lockedAmount
            );
            // NOTE: If we could not burn the full locked amount, set the remaining amount and make the lock infinite.
            //       Remove the lock if nothing is left to burn.
            CSBondLock._changeBondLock({
                nodeOperatorId: nodeOperatorId,
                amount: notBurnedAmount,
                until: INFINITE_BOND_LOCK_UNTIL
            });
            _adjustBondReserve(nodeOperatorId);
            applied = true;
        }
    }

    /// @inheritdoc ICSAccounting
    function penalize(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyModule returns (bool fullyBurned) {
        uint256 notBurnedAmount = CSBondCore._burn(nodeOperatorId, amount);
        fullyBurned = notBurnedAmount == 0;
        if (!fullyBurned) {
            // NOTE:  If we could not burn the full amount, add the remaining to the current lock and make it infinite.
            uint256 locked = CSBondLock.getActualLockedBond(nodeOperatorId);
            CSBondLock._changeBondLock({
                nodeOperatorId: nodeOperatorId,
                amount: locked + notBurnedAmount,
                until: INFINITE_BOND_LOCK_UNTIL
            });
        }
        _adjustBondReserve(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function chargeFee(
        uint256 nodeOperatorId,
        uint256 amount
    ) external onlyModule returns (bool fullyCharged) {
        fullyCharged = CSBondCore._charge(
            nodeOperatorId,
            amount,
            chargePenaltyRecipient
        );
        _adjustBondReserve(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
    function pullAndSplitFeeRewards(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external {
        _onlyExistingNodeOperator(nodeOperatorId);
        _pullAndSplitFeeRewards(
            nodeOperatorId,
            cumulativeFeeShares,
            rewardsProof
        );
        MODULE.updateDepositableValidatorsCount(nodeOperatorId);
    }

    /// @inheritdoc AssetRecoverer
    function recoverERC20(address token, uint256 amount) external override {
        _onlyRecoverer();
        if (token == address(LIDO)) {
            revert NotAllowedToRecover();
        }
        AssetRecovererLib.recoverERC20(token, amount);
    }

    /// @notice Recover all stETH shares from the contract
    /// @dev Accounts for the bond funds stored during recovery
    function recoverStETHShares() external {
        _onlyRecoverer();
        uint256 shares = LIDO.sharesOf(address(this)) - totalBondShares();
        AssetRecovererLib.recoverStETHShares(address(LIDO), shares);
    }

    /// @inheritdoc ICSAccounting
    function renewBurnerAllowance() external {
        LIDO.approve(LIDO_LOCATOR.burner(), type(uint256).max);
    }

    /// @inheritdoc ICSAccounting
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc ICSAccounting
    function getFeeSplits(
        uint256 nodeOperatorId
    ) external view returns (FeeSplit[] memory) {
        return _feeSplits[nodeOperatorId];
    }

    /// @inheritdoc ICSAccounting
    function getPendingSharesToSplit(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        return _pendingSharesToSplit[nodeOperatorId];
    }

    /// @inheritdoc ICSAccounting
    function getUnbondedKeysCount(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        return
            _getUnbondedKeysCount({
                nodeOperatorId: nodeOperatorId,
                includeLockedBond: true
            });
    }

    /// @inheritdoc ICSAccounting
    function getUnbondedKeysCountToEject(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        return
            _getUnbondedKeysCount({
                nodeOperatorId: nodeOperatorId,
                includeLockedBond: false
            });
    }

    /// @inheritdoc ICSAccounting
    function getBondAmountByKeysCountWstETH(
        uint256 keysCount,
        uint256 curveId
    ) external view returns (uint256) {
        return
            _sharesByEth(
                CSBondCurve.getBondAmountByKeysCount(keysCount, curveId)
            );
    }

    /// @inheritdoc ICSAccounting
    function getRequiredBondForNextKeysWstETH(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) external view returns (uint256) {
        return
            _sharesByEth(
                getRequiredBondForNextKeys(nodeOperatorId, additionalKeys)
            );
    }

    /// @inheritdoc ICSAccounting
    function getClaimableBondShares(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        return _getClaimableBondShares(nodeOperatorId);
    }

    /// @inheritdoc ICSAccounting
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

        (uint256 current, uint256 required) = getBondSummaryShares(
            nodeOperatorId
        );
        current = current + feesToDistribute;

        return current > required ? current - required : 0;
    }

    /// @inheritdoc ICSAccounting
    function canRemoveBondReserve(
        uint256 nodeOperatorId
    ) external view whenBondReserveIsEnabled returns (bool) {
        IBondReserve.BondReserveInfo memory r = BondReserve.getBondReserveInfo(
            nodeOperatorId
        );
        return _canRemoveBondReserve(nodeOperatorId, r);
    }

    /// @inheritdoc ICSAccounting
    function getBondSummary(
        uint256 nodeOperatorId
    ) public view returns (uint256 current, uint256 required) {
        current = CSBondCore.getBond(nodeOperatorId);
        required = _getRequiredBond(nodeOperatorId, 0);
    }

    /// @inheritdoc ICSAccounting
    function getBondSummaryShares(
        uint256 nodeOperatorId
    ) public view returns (uint256 current, uint256 required) {
        current = CSBondCore.getBondShares(nodeOperatorId);
        required = _getRequiredBondShares(nodeOperatorId, 0);
    }

    /// @inheritdoc ICSAccounting
    function getRequiredBondForNextKeys(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) public view returns (uint256) {
        uint256 current = CSBondCore.getBond(nodeOperatorId);
        uint256 totalRequired = _getRequiredBond(
            nodeOperatorId,
            additionalKeys
        );

        unchecked {
            return totalRequired > current ? totalRequired - current : 0;
        }
    }

    function _pullAndSplitFeeRewards(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) internal returns (uint256 claimableShares) {
        bool hasSplits = FeeSplits.hasSplits(_feeSplits, nodeOperatorId);
        if (rewardsProof.length != 0) {
            uint256 distributed = FEE_DISTRIBUTOR.distributeFees(
                nodeOperatorId,
                cumulativeFeeShares,
                rewardsProof
            );
            if (distributed != 0) {
                CSBondCore._increaseBond(nodeOperatorId, distributed);
                if (hasSplits) {
                    _pendingSharesToSplit[nodeOperatorId] += distributed;
                }
            }
        }
        claimableShares = _getClaimableBondShares(nodeOperatorId);
        if (hasSplits) {
            uint256 transferredShares = FeeSplits.splitAndTransferFees({
                feeSplitsStorage: _feeSplits,
                pendingSharesToSplitStorage: _pendingSharesToSplit,
                lido: LIDO,
                nodeOperatorId: nodeOperatorId,
                maxSharesToSplit: claimableShares
            });
            if (transferredShares != 0) {
                CSBondCore._unsafeReduceBond(nodeOperatorId, transferredShares);
                // @dev It is safe to use unchecked here since `transferredShares` is always <= `claimableShares`
                unchecked {
                    claimableShares -= transferredShares;
                }
            }
        }
    }

    function _unwrapStETHPermitIfRequired(
        address from,
        PermitInput calldata permit
    ) internal {
        if (
            permit.value > 0 &&
            LIDO.allowance(from, address(this)) < permit.value
        ) {
            LIDO.permit({
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

    function _unwrapWstETHPermitIfRequired(
        address from,
        PermitInput calldata permit
    ) internal {
        if (
            permit.value > 0 &&
            WSTETH.allowance(from, address(this)) < permit.value
        ) {
            WSTETH.permit({
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

    function _adjustBondReserve(uint256 nodeOperatorId) internal {
        if (!BOND_RESERVE_IS_ENABLED) {
            return;
        }
        uint256 reserved = BondReserve.getReservedBond(nodeOperatorId);
        if (reserved == 0) {
            return;
        }
        uint256 current = CSBondCore.getBond(nodeOperatorId);
        if (current < reserved) {
            /*
            CURRENT = EXCESS + REQUIRED_FOR_KEYS + RESERVE
            TOTAL_REQUIRED = REQUIRED_FOR_KEYS + RESERVE + LOCK
            EXCESS = max(CURRENT - TOTAL_REQUIRED, 0)
            Shrinking flow: EXCESS -> REQUIRED_FOR_KEYS -> RESERVE
            ---
            There is an invariant that RESERVE can't be greater than CURRENT; RESERVE is part of CURRENT.
            We need to follow this invariant and must shrink RESERVE last.
        */
            BondReserve._setBondReserve(nodeOperatorId, current);
        }
    }

    /// @dev Calculates claimable bond shares accounting for locked bond and withdrawn validators
    function _getClaimableBondShares(
        uint256 nodeOperatorId
    ) internal view returns (uint256) {
        unchecked {
            (
                uint256 currentShares,
                uint256 requiredShares
            ) = getBondSummaryShares(nodeOperatorId);
            return
                currentShares > requiredShares
                    ? currentShares - requiredShares
                    : 0;
        }
    }

    function _getRequiredBond(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) internal view returns (uint256) {
        uint256 curveId = CSBondCurve.getBondCurveId(nodeOperatorId);
        uint256 nonWithdrawnKeys = MODULE.getNodeOperatorNonWithdrawnKeys(
            nodeOperatorId
        );
        uint256 requiredBondForKeys = CSBondCurve.getBondAmountByKeysCount(
            nonWithdrawnKeys + additionalKeys,
            curveId
        );
        uint256 actualLockedBond = CSBondLock.getActualLockedBond(
            nodeOperatorId
        );
        uint256 reserved = BondReserve.getReservedBond(nodeOperatorId);

        return requiredBondForKeys + actualLockedBond + reserved;
    }

    function _getRequiredBondShares(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) internal view returns (uint256) {
        return _sharesByEth(_getRequiredBond(nodeOperatorId, additionalKeys));
    }

    /// @dev Unbonded stands for the amount of keys not fully covered with bond
    function _getUnbondedKeysCount(
        uint256 nodeOperatorId,
        bool includeLockedBond
    ) internal view returns (uint256) {
        uint256 nonWithdrawnKeys = MODULE.getNodeOperatorNonWithdrawnKeys(
            nodeOperatorId
        );
        uint256 currentBond = CSBondCore.getBond(nodeOperatorId);
        {
            uint256 reservedBond = BondReserve.getReservedBond(nodeOperatorId);
            // NOTE: `reservedBond` cannot exceed `currentBond` because it can be created
            // only from the excess bond portion (current - required > 0).
            currentBond -= reservedBond;
        }

        // Optionally account for locked bond depending on the flag
        if (includeLockedBond) {
            uint256 lockedBond = CSBondLock.getActualLockedBond(nodeOperatorId);
            // We use strict condition here since in rare case of equality the outcome of the function will not change
            if (lockedBond > currentBond) {
                return nonWithdrawnKeys;
            }
            currentBond -= lockedBond;
        }
        // 10 wei is added to account for possible stETH rounding errors
        // https://github.com/lidofinance/lido-dao/issues/442#issuecomment-1182264205.
        // Should be sufficient for ~ 40 years
        uint256 bondedKeys = CSBondCurve.getKeysCountByBondAmount(
            currentBond + 10 wei,
            CSBondCurve.getBondCurveId(nodeOperatorId)
        );
        return
            nonWithdrawnKeys > bondedKeys ? nonWithdrawnKeys - bondedKeys : 0;
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (
            nodeOperatorId <
            IStakingModule(address(MODULE)).getNodeOperatorsCount()
        ) {
            return;
        }

        revert NodeOperatorDoesNotExist();
    }

    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        if (MODULE.getNodeOperatorOwner(nodeOperatorId) != msg.sender) {
            revert SenderIsNotEligible();
        }
    }

    function _checkAndGetEligibleNodeOperatorProperties(
        uint256 nodeOperatorId
    ) internal view returns (NodeOperatorManagementProperties memory no) {
        no = MODULE.getNodeOperatorManagementProperties(nodeOperatorId);
        if (no.managerAddress == address(0)) {
            revert NodeOperatorDoesNotExist();
        }

        if (no.managerAddress != msg.sender && no.rewardAddress != msg.sender) {
            revert SenderIsNotEligible();
        }
    }

    /// @dev Bond reserve can be removed if a sufficient time has passed or if the Node Operator has no active or depositable keys
    function _canRemoveBondReserve(
        uint256 nodeOperatorId,
        IBondReserve.BondReserveInfo memory r
    ) internal view returns (bool isRemovable) {
        isRemovable =
            block.timestamp >= uint256(r.removableAt) ||
            MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId) == 0;
    }

    function _setChargePenaltyRecipient(
        address _chargePenaltyRecipient
    ) private {
        if (_chargePenaltyRecipient == address(0)) {
            revert ZeroChargePenaltyRecipientAddress();
        }
        chargePenaltyRecipient = _chargePenaltyRecipient;
        emit ChargePenaltyRecipientSet(_chargePenaltyRecipient);
    }
}
