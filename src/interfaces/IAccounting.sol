// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";

import { IBondCore } from "./IBondCore.sol";
import { IBondCurve } from "./IBondCurve.sol";
import { IBondLock } from "./IBondLock.sol";
import { IFeeDistributor } from "./IFeeDistributor.sol";
import { IBaseModule } from "./IBaseModule.sol";

interface IAccounting is IBondCore, IBondCurve, IBondLock, IAssetRecovererLib {
    struct PermitInput {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct FeeSplit {
        address recipient;
        uint256 share; // in basis points
    }

    event BondLockCompensated(uint256 indexed nodeOperatorId, uint256 amount);
    event ChargePenaltyRecipientSet(address chargePenaltyRecipient);
    event CustomRewardsClaimerSet(
        uint256 indexed nodeOperatorId,
        address rewardsClaimer
    );

    error SenderIsNotModule();
    error SenderIsNotEligible();
    error ZeroModuleAddress();
    error ZeroAdminAddress();
    error ZeroFeeDistributorAddress();
    error ZeroChargePenaltyRecipientAddress();
    error NodeOperatorDoesNotExist();
    error ElRewardsVaultReceiveFailed();
    error InvalidBondCurvesLength();
    error SameAddress();

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function MANAGE_BOND_CURVES_ROLE() external view returns (bytes32);

    function SET_BOND_CURVE_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    function MODULE() external view returns (IBaseModule);

    function FEE_DISTRIBUTOR() external view returns (IFeeDistributor);

    function chargePenaltyRecipient() external view returns (address);

    /// @notice Get the initialized version of the contract
    function getInitializedVersion() external view returns (uint64);

    /// @notice Resume reward claims and deposits
    function resume() external;

    /// @notice Pause reward claims and deposits for `duration` seconds
    /// @dev Must be called together with `CSModule.pauseFor`
    /// @dev Passing MAX_UINT_256 as `duration` pauses indefinitely
    /// @param duration Duration of the pause in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Set charge recipient address
    /// @param _chargePenaltyRecipient Charge recipient address
    function setChargePenaltyRecipient(
        address _chargePenaltyRecipient
    ) external;

    /// @notice Set bond lock period
    /// @param period Period in seconds to retain bond lock
    function setBondLockPeriod(uint256 period) external;

    /// @notice Set fee splits for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    /// @param feeSplits Array of FeeSplit structs defining recipients and their shares in basis points
    ///                  Total shares must be <= 10_000 (100%). Remainder goes to the Node Operator's bond
    function setFeeSplits(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof,
        FeeSplit[] calldata feeSplits
    ) external;

    /// @notice Add a new bond curve
    /// @param bondCurve Bond curve definition to add
    /// @return id Id of the added curve
    function addBondCurve(
        BondCurveIntervalInput[] calldata bondCurve
    ) external returns (uint256 id);

    /// @notice Update existing bond curve
    /// @dev If the curve is updated to a curve with higher values for any point,
    ///      Extensive checks and actions should be performed by the method caller to avoid
    ///      inconsistency in the keys accounting. A manual update of the depositable validators count
    ///      in staking module might be required to ensure that the keys pointers are consistent.
    /// @param curveId Bond curve ID to update
    /// @param bondCurve Bond curve definition
    function updateBondCurve(
        uint256 curveId,
        BondCurveIntervalInput[] calldata bondCurve
    ) external;

    /// @notice Set custom rewards claimer for the given Node Operator. This address will be able to claim rewards on behalf of the Node Operator.
    ///         The rewards will be transferred to the Node Operator's reward address as usual.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param rewardsClaimer Address allowed to claim rewards on behalf of the Node Operator
    function setCustomRewardsClaimer(
        uint256 nodeOperatorId,
        address rewardsClaimer
    ) external;

    /// @notice Get the custom rewards claimer for the given Node Operator. This address is allowed to claim rewards on behalf of the Node Operator.
    ///         The rewards are still transferred to the Node Operator's reward address as usual.
    /// @param nodeOperatorId ID of the Node Operator
    /// @return rewardsClaimer Address allowed to claim rewards on behalf of the Node Operator
    function getCustomRewardsClaimer(
        uint256 nodeOperatorId
    ) external view returns (address);

    /// @notice Get the required bond in ETH (inc. missed and excess) for the given Node Operator to upload new deposit data
    /// @param nodeOperatorId ID of the Node Operator
    /// @param additionalKeys Number of new keys to add
    /// @return Required bond amount in ETH
    function getRequiredBondForNextKeys(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) external view returns (uint256);

    /// @notice Get the bond amount in wstETH required for the `keysCount` keys using the default bond curve
    /// @param keysCount Keys count to calculate the required bond amount
    /// @param curveId Id of the curve to perform calculations against
    /// @return wstETH amount required for the `keysCount`
    function getBondAmountByKeysCountWstETH(
        uint256 keysCount,
        uint256 curveId
    ) external view returns (uint256);

    /// @notice Get the required bond in wstETH (inc. missed and excess) for the given Node Operator to upload new keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @param additionalKeys Number of new keys to add
    /// @return Required bond in wstETH
    function getRequiredBondForNextKeysWstETH(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) external view returns (uint256);

    /// @notice Set fee splits for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Array of FeeSplit structs defining recipients and their shares in basis points
    function getFeeSplits(
        uint256 nodeOperatorId
    ) external view returns (FeeSplit[] memory);

    /// @notice Get the number of the pending shares to be split for the given Node Operator
    function getPendingSharesToSplit(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get the number of the unbonded keys
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Unbonded keys count
    function getUnbondedKeysCount(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get the number of the unbonded keys to be ejected using a forcedTargetLimit
    ///         Locked bond is not considered for this calculation to allow Node Operators to
    ///         compensate the locked bond via `compensateLockedBondETH` method before the ejection happens
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Unbonded keys count
    function getUnbondedKeysCountToEject(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get current and required bond amounts in ETH (stETH) for the given Node Operator
    /// @dev To calculate excess bond amount subtract `required` from `current` value.
    ///      To calculate missed bond amount subtract `current` from `required` value
    /// @param nodeOperatorId ID of the Node Operator
    /// @return current Current bond amount in ETH
    /// @return required Required bond amount in ETH
    function getBondSummary(
        uint256 nodeOperatorId
    ) external view returns (uint256 current, uint256 required);

    /// @notice Get current and required bond amounts in stETH shares for the given Node Operator
    /// @dev To calculate excess bond amount subtract `required` from `current` value.
    ///      To calculate missed bond amount subtract `current` from `required` value
    /// @param nodeOperatorId ID of the Node Operator
    /// @return current Current bond amount in stETH shares
    /// @return required Required bond amount in stETH shares
    function getBondSummaryShares(
        uint256 nodeOperatorId
    ) external view returns (uint256 current, uint256 required);

    /// @notice Get current claimable bond in stETH shares for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Current claimable bond in stETH shares
    function getClaimableBondShares(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get current claimable bond in stETH shares for the given Node Operator
    ///         Includes potential rewards distributed by the Fee Distributor
    /// @param nodeOperatorId ID of the Node Operator
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    /// @return Current claimable bond in stETH shares
    function getClaimableRewardsAndBondShares(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external view returns (uint256);

    /// @notice Unwrap the user's wstETH and deposit stETH to the bond for the given Node Operator
    /// @dev Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count
    /// @param from Address to unwrap wstETH from
    /// @param nodeOperatorId ID of the Node Operator
    /// @param wstETHAmount Amount of wstETH to deposit
    /// @param permit wstETH permit for the contract
    function depositWstETH(
        address from,
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external;

    /// @notice Unwrap the user's wstETH and deposit stETH to the bond for the given Node Operator
    /// @dev Permissionless. Enqueues Node Operator's keys if needed
    /// @param nodeOperatorId ID of the Node Operator
    /// @param wstETHAmount Amount of wstETH to deposit
    /// @param permit wstETH permit for the contract
    function depositWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        PermitInput calldata permit
    ) external;

    /// @notice Deposit user's stETH to the bond for the given Node Operator
    /// @dev Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count
    /// @param from Address to deposit stETH from.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param stETHAmount Amount of stETH to deposit
    /// @param permit stETH permit for the contract
    function depositStETH(
        address from,
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external;

    /// @notice Deposit user's stETH to the bond for the given Node Operator
    /// @dev Permissionless. Enqueues Node Operator's keys if needed
    /// @param nodeOperatorId ID of the Node Operator
    /// @param stETHAmount Amount of stETH to deposit
    /// @param permit stETH permit for the contract
    function depositStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        PermitInput calldata permit
    ) external;

    /// @notice Stake user's ETH with Lido and deposit stETH to the bond
    /// @dev Called by staking module exclusively. Staking module should check node operator existence and update depositable validators count
    /// @param from Address to stake ETH and deposit stETH from
    /// @param nodeOperatorId ID of the Node Operator
    function depositETH(address from, uint256 nodeOperatorId) external payable;

    /// @notice Stake user's ETH with Lido and deposit stETH to the bond
    /// @dev Permissionless. Enqueues Node Operator's keys if needed
    /// @param nodeOperatorId ID of the Node Operator
    function depositETH(uint256 nodeOperatorId) external payable;

    /// @notice Claim full reward (fee + bond) in stETH for the given Node Operator with desirable value.
    ///         `rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond
    /// @param nodeOperatorId ID of the Node Operator
    /// @param stETHAmount Amount of stETH to claim
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    /// @return shares Amount of stETH shares claimed
    /// @dev It's impossible to use single-leaf proof via this method, so this case should be treated carefully by
    /// off-chain tooling, e.g. to make sure a tree has at least 2 leaves.
    function claimRewardsStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external returns (uint256 shares);

    /// @notice Claim full reward (fee + bond) in wstETH for the given Node Operator available for this moment.
    ///         `rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond
    /// @param nodeOperatorId ID of the Node Operator
    /// @param wstETHAmount Amount of wstETH to claim
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    /// @return claimedWstETHAmount Amount of wstETH claimed
    /// @dev It's impossible to use single-leaf proof via this method, so this case should be treated carefully by
    /// off-chain tooling, e.g. to make sure a tree has at least 2 leaves.
    function claimRewardsWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external returns (uint256 claimedWstETHAmount);

    /// @notice Request full reward (fee + bond) in Withdrawal NFT (unstETH) for the given Node Operator available for this moment.
    ///         `rewardsProof` and `cumulativeFeeShares` might be empty in order to claim only excess bond
    /// @dev Reverts if amount isn't between `MIN_STETH_WITHDRAWAL_AMOUNT` and `MAX_STETH_WITHDRAWAL_AMOUNT`
    /// @param nodeOperatorId ID of the Node Operator
    /// @param stETHAmount Amount of ETH to request
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    /// @return requestId Withdrawal NFT ID
    /// @dev It's impossible to use single-leaf proof via this method, so this case should be treated carefully by
    /// off-chain tooling, e.g. to make sure a tree has at least 2 leaves.
    function claimRewardsUnstETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external returns (uint256 requestId);

    /// @notice Lock bond in ETH for the given Node Operator
    /// @dev Called by staking module exclusively
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount to lock in ETH (stETH)
    function lockBondETH(uint256 nodeOperatorId, uint256 amount) external;

    /// @notice Release locked bond in ETH for the given Node Operator
    /// @dev Called by staking module exclusively
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount to release in ETH (stETH)
    function releaseLockedBondETH(
        uint256 nodeOperatorId,
        uint256 amount
    ) external;

    /// @notice Settle locked bond ETH for the given Node Operator
    /// @dev Called by staking module exclusively
    /// @param nodeOperatorId ID of the Node Operator
    function settleLockedBondETH(
        uint256 nodeOperatorId
    ) external returns (bool);

    /// @notice Compensate locked bond ETH for the given Node Operator
    /// @dev Called by staking module exclusively
    /// @param nodeOperatorId ID of the Node Operator
    function compensateLockedBondETH(uint256 nodeOperatorId) external payable;

    /// @notice Set the bond curve for the given Node Operator
    /// @dev Updates depositable validators count in staking module to ensure key pointers consistency
    /// @param nodeOperatorId ID of the Node Operator
    /// @param curveId ID of the bond curve to set
    function setBondCurve(uint256 nodeOperatorId, uint256 curveId) external;

    /// @notice Penalize bond by burning stETH shares of the given Node Operator
    /// @dev Penalty application has a priority over the locked bond.
    ///      Method call can result in the remaining bond being lower than the locked bond.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount to penalize in ETH (stETH)
    /// @return fullyBurned True if the bond was fully burned, false otherwise
    function penalize(
        uint256 nodeOperatorId,
        uint256 amount
    ) external returns (bool fullyBurned);

    /// @notice Charge fee from bond by transferring stETH shares of the given Node Operator to the charge recipient
    /// @dev Charge confiscation has a priority over the locked bond.
    ///      Method call can result in the remaining bond being lower than the locked bond.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param amount Amount to charge in ETH (stETH)
    /// @return fullyCharged True if the bond was fully charged, false otherwise
    function chargeFee(
        uint256 nodeOperatorId,
        uint256 amount
    ) external returns (bool fullyCharged);

    /// @notice Pull fees (if proof provided) from FeeDistributor to the Node Operator's bond and split pending according to configured fee splits.
    /// @dev Permissionless method. Can be called before penalty application to ensure that rewards are also penalized and split.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param cumulativeFeeShares Cumulative fee stETH shares for the Node Operator
    /// @param rewardsProof Merkle proof of the rewards
    function pullAndSplitFeeRewards(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata rewardsProof
    ) external;

    /// @notice Service method to update allowance to Burner in case it has changed
    function renewBurnerAllowance() external;
}
