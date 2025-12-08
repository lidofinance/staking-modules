// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";
import { IStETH } from "./IStETH.sol";

pragma solidity 0.8.31;

interface IFeeDistributor is IAssetRecovererLib {
    struct DistributionData {
        /// @dev Reference slot for which the report was calculated. If the slot
        /// contains a block, the state being reported should include all state
        /// changes resulting from that block. The epoch containing the slot
        /// should be finalized prior to calculating the report.
        uint256 refSlot;
        /// @notice Merkle Tree root.
        bytes32 treeRoot;
        /// @notice CID of the published Merkle tree.
        string treeCid;
        /// @notice CID of the file with log of the frame reported.
        string logCid;
        /// @notice Total amount of fees distributed in the report.
        uint256 distributed;
        /// @notice Amount of the rebate shares in the report
        uint256 rebate;
    }

    /// @dev Emitted when fees are distributed
    event OperatorFeeDistributed(
        uint256 indexed nodeOperatorId,
        uint256 shares
    );

    /// @dev Emitted when distribution data is updated
    event DistributionDataUpdated(
        uint256 totalClaimableShares,
        bytes32 treeRoot,
        string treeCid
    );

    /// @dev Emitted when distribution log is updated
    event DistributionLogUpdated(string logCid);

    /// @dev It logs how many shares were distributed in the latest report
    event ModuleFeeDistributed(uint256 shares);

    /// @dev Emitted when rebate is transferred
    event RebateTransferred(uint256 shares);

    /// @dev Emitted when rebate recipient is set
    event RebateRecipientSet(address recipient);

    error ZeroAccountingAddress();
    error ZeroStEthAddress();
    error ZeroAdminAddress();
    error ZeroOracleAddress();
    error ZeroRebateRecipientAddress();
    error SenderIsNotAccounting();
    error SenderIsNotOracle();

    error InvalidReportData();
    error InvalidTreeRoot();
    error InvalidTreeCid();
    error InvalidLogCID();
    error InvalidShares();
    error InvalidProof();
    error FeeSharesDecrease();
    error NotEnoughShares();

    function RECOVERER_ROLE() external view returns (bytes32);

    function STETH() external view returns (IStETH);

    function ACCOUNTING() external view returns (address);

    function ORACLE() external view returns (address);

    function treeRoot() external view returns (bytes32);

    function treeCid() external view returns (string calldata);

    function logCid() external view returns (string calldata);

    function distributedShares(uint256) external view returns (uint256);

    function totalClaimableShares() external view returns (uint256);

    function distributionDataHistoryCount() external view returns (uint256);

    function rebateRecipient() external view returns (address);

    /// @notice Get the initialized version of the contract
    function getInitializedVersion() external view returns (uint64);

    /// @notice Set address to send rebate to
    /// @param _rebateRecipient Address to send rebate to
    function setRebateRecipient(address _rebateRecipient) external;

    /// @notice Get the Amount of stETH shares that can be distributed in favor of the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param cumulativeFeeShares Total Amount of stETH shares earned as fees
    /// @param proof Merkle proof of the leaf
    /// @return sharesToDistribute Amount of stETH shares that can be distributed
    function getFeesToDistribute(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata proof
    ) external view returns (uint256);

    /// @notice Distribute fees to the Accounting in favor of the Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param cumulativeFeeShares Total Amount of stETH shares earned as fees
    /// @param proof Merkle proof of the leaf
    /// @return sharesToDistribute Amount of stETH shares distributed
    function distributeFees(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata proof
    ) external returns (uint256);

    /// @notice Receive the data of the Merkle tree from the Oracle contract and process it
    /// @param _treeRoot Root of the Merkle tree
    /// @param _treeCid an IPFS CID of the tree
    /// @param _logCid an IPFS CID of the log
    /// @param distributed an amount of the distributed shares
    /// @param rebate an amount of the rebate shares
    /// @param refSlot refSlot of the report
    function processOracleReport(
        bytes32 _treeRoot,
        string calldata _treeCid,
        string calldata _logCid,
        uint256 distributed,
        uint256 rebate,
        uint256 refSlot
    ) external;

    /// @notice Get the Amount of stETH shares that are pending to be distributed
    /// @return pendingShares Amount shares that are pending to distribute
    function pendingSharesToDistribute() external view returns (uint256);

    /// @notice Get the historical record of distribution data
    /// @param index Historical entry index
    /// @return Historical distribution data
    function getHistoricalDistributionData(
        uint256 index
    ) external view returns (DistributionData memory);

    /// @notice Get a hash of a leaf
    /// @param nodeOperatorId ID of the Node Operator
    /// @param shares Amount of stETH shares
    /// @return Hash of the leaf
    /// @dev Double hash the leaf to prevent second preimage attacks
    function hashLeaf(
        uint256 nodeOperatorId,
        uint256 shares
    ) external pure returns (bytes32);
}
