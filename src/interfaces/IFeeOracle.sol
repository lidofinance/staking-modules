// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAssetRecovererLib } from "../lib/AssetRecovererLib.sol";
import { IFeeDistributor } from "./IFeeDistributor.sol";
import { IValidatorStrikes } from "./IValidatorStrikes.sol";

interface IFeeOracle is IAssetRecovererLib {
    struct ReportData {
        /// @dev Version of the oracle consensus rules. Current version expected
        /// by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
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
        /// @notice Merkle Tree root of the strikes.
        bytes32 strikesTreeRoot;
        /// @notice CID of the published Merkle tree of the strikes.
        string strikesTreeCid;
    }

    error ZeroAdminAddress();
    error ZeroFeeDistributorAddress();
    error ZeroStrikesAddress();
    error SenderNotAllowed();

    function SUBMIT_DATA_ROLE() external view returns (bytes32);

    function FEE_DISTRIBUTOR() external view returns (IFeeDistributor);

    function STRIKES() external view returns (IValidatorStrikes);

    /// @notice Submit the data for a committee report
    /// @param data Data for a committee report
    /// @param contractVersion Expected storage contract version of the FeeOracle implementation
    function submitReportData(ReportData calldata data, uint256 contractVersion) external;
}
