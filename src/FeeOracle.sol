// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { PausableWithRoles } from "./abstract/PausableWithRoles.sol";
import { BaseOracle } from "./lib/base-oracle/BaseOracle.sol";

import { IValidatorStrikes } from "./interfaces/IValidatorStrikes.sol";
import { IFeeDistributor } from "./interfaces/IFeeDistributor.sol";
import { IFeeOracle } from "./interfaces/IFeeOracle.sol";

contract FeeOracle is IFeeOracle, BaseOracle, PausableWithRoles, AssetRecoverer {
    uint256 internal constant INITIALIZED_VERSION = 3;

    /// @dev No assets are stored in the contract

    /// @notice An ACL role granting the permission to submit the data for a committee report.
    bytes32 public constant SUBMIT_DATA_ROLE = keccak256("SUBMIT_DATA_ROLE");

    IFeeDistributor public immutable FEE_DISTRIBUTOR;
    IValidatorStrikes public immutable STRIKES;

    bytes32 internal __freeSlot1;
    bytes32 internal __freeSlot2;

    constructor(
        address feeDistributor,
        address strikes,
        uint256 secondsPerSlot,
        uint256 genesisTime
    ) BaseOracle(secondsPerSlot, genesisTime) {
        if (feeDistributor == address(0)) revert ZeroFeeDistributorAddress();
        if (strikes == address(0)) revert ZeroStrikesAddress();

        FEE_DISTRIBUTOR = IFeeDistributor(feeDistributor);
        STRIKES = IValidatorStrikes(strikes);
    }

    /// @dev Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
    ///      It is recommended to call this method in the same transaction as the deployment transaction
    ///      and perform extensive deployment verification before using the contract instance.
    function initialize(address admin, address consensusContract, uint256 consensusVersion) external {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        BaseOracle._initialize(consensusContract, consensusVersion, 0);

        for (uint256 version = 2; version <= INITIALIZED_VERSION; version++) {
            _updateContractVersion(version);
        }
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
    ///      If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
    ///      To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.
    function finalizeUpgradeV3(uint256 consensusVersion) external {
        _setConsensusVersion(consensusVersion);
        _updateContractVersion(INITIALIZED_VERSION);
    }

    /// @inheritdoc IFeeOracle
    function submitReportData(ReportData calldata data, uint256 contractVersion) external whenResumed {
        _checkMsgSenderIsAllowedToSubmitData();
        _checkContractVersion(contractVersion);
        _checkConsensusData(
            data.refSlot,
            data.consensusVersion,
            // it's a waste of gas to copy the whole calldata into mem but seems there's no way around
            keccak256(abi.encode(data))
        );
        _startProcessing();
        _handleConsensusReportData(data);
    }

    /// @dev Called in `submitConsensusReport` after a consensus is reached.
    function _handleConsensusReport(
        ConsensusReport memory /* report */,
        uint256 /* prevSubmittedRefSlot */,
        uint256 /* prevProcessingRefSlot */
    ) internal override {
        // solhint-disable-previous-line no-empty-blocks
        // We do not require any type of async processing so far, so no actions required.
    }

    function _handleConsensusReportData(ReportData calldata data) internal {
        FEE_DISTRIBUTOR.processOracleReport({
            _treeRoot: data.treeRoot,
            _treeCid: data.treeCid,
            _logCid: data.logCid,
            distributed: data.distributed,
            rebate: data.rebate,
            refSlot: data.refSlot
        });
        STRIKES.processOracleReport(data.strikesTreeRoot, data.strikesTreeCid);
    }

    function _checkMsgSenderIsAllowedToSubmitData() internal view {
        if (_isConsensusMember(msg.sender) || hasRole(SUBMIT_DATA_ROLE, msg.sender)) return;
        revert SenderNotAllowed();
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
