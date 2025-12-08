// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { AssetRecovererLib } from "./lib/AssetRecovererLib.sol";

import { IFeeDistributor } from "./interfaces/IFeeDistributor.sol";
import { IStETH } from "./interfaces/IStETH.sol";

/// @author madlabman
contract FeeDistributor is
    IFeeDistributor,
    Initializable,
    AccessControlEnumerableUpgradeable,
    AssetRecoverer
{
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");

    IStETH public immutable STETH;
    address public immutable ACCOUNTING;
    address public immutable ORACLE;

    /// @notice The latest Merkle Tree root
    bytes32 public treeRoot;

    /// @notice CID of the last published Merkle tree
    string public treeCid;

    /// @notice CID of the file with log for the last frame reported
    string public logCid;

    /// @notice Amount of stETH shares sent to the Accounting in favor of the NO
    mapping(uint256 nodeOperatorId => uint256 distributed)
        public distributedShares;

    /// @notice Total Amount of stETH shares available for claiming by NOs
    uint256 public totalClaimableShares;

    /// @notice Array of the distribution data history
    mapping(uint256 index => DistributionData)
        internal _distributionDataHistory;

    /// @notice The number of _distributionDataHistory records
    uint256 public distributionDataHistoryCount;

    /// @notice The address to transfer rebate to
    address public rebateRecipient;

    modifier onlyAccounting() {
        _onlyAccounting();
        _;
    }

    modifier onlyOracle() {
        _onlyOracle();
        _;
    }

    constructor(address stETH, address accounting, address oracle) {
        if (accounting == address(0)) {
            revert ZeroAccountingAddress();
        }
        if (oracle == address(0)) {
            revert ZeroOracleAddress();
        }

        if (stETH == address(0)) {
            revert ZeroStEthAddress();
        }

        ACCOUNTING = accounting;
        STETH = IStETH(stETH);
        ORACLE = oracle;

        _disableInitializers();
    }

    function initialize(
        address admin,
        address _rebateRecipient
    ) external reinitializer(2) {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        _setRebateRecipient(_rebateRecipient);

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 1 to version 2 for the existing version 1 deployment.
    ///      If the version 2 contract is deployed from scratch, the `initialize` method should be used instead.
    function finalizeUpgradeV2(
        address _rebateRecipient
    ) external reinitializer(2) {
        _setRebateRecipient(_rebateRecipient);
    }

    /// @inheritdoc IFeeDistributor
    function setRebateRecipient(
        address _rebateRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRebateRecipient(_rebateRecipient);
    }

    /// @inheritdoc IFeeDistributor
    function distributeFees(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata proof
    ) external onlyAccounting returns (uint256 sharesToDistribute) {
        sharesToDistribute = getFeesToDistribute(
            nodeOperatorId,
            cumulativeFeeShares,
            proof
        );

        if (sharesToDistribute == 0) {
            return 0;
        }

        if (totalClaimableShares < sharesToDistribute) {
            revert NotEnoughShares();
        }

        unchecked {
            totalClaimableShares -= sharesToDistribute;
            distributedShares[nodeOperatorId] += sharesToDistribute;
        }

        STETH.transferShares(ACCOUNTING, sharesToDistribute);
        emit OperatorFeeDistributed(nodeOperatorId, sharesToDistribute);
    }

    /// @inheritdoc IFeeDistributor
    function processOracleReport(
        bytes32 _treeRoot,
        string calldata _treeCid,
        string calldata _logCid,
        uint256 distributed,
        uint256 rebate,
        uint256 refSlot
    ) external onlyOracle {
        if (
            totalClaimableShares + distributed + rebate >
            STETH.sharesOf(address(this))
        ) {
            revert InvalidShares();
        }

        if (distributed == 0 && rebate > 0) {
            revert InvalidReportData();
        }

        if (distributed > 0) {
            if (bytes(_treeCid).length == 0) {
                revert InvalidTreeCid();
            }
            if (keccak256(bytes(_treeCid)) == keccak256(bytes(treeCid))) {
                revert InvalidTreeCid();
            }

            if (_treeRoot == bytes32(0)) {
                revert InvalidTreeRoot();
            }
            if (_treeRoot == treeRoot) {
                revert InvalidTreeRoot();
            }

            // Doesn't overflow because of the very first check.
            unchecked {
                totalClaimableShares += distributed;
            }

            treeRoot = _treeRoot;
            treeCid = _treeCid;

            emit DistributionDataUpdated(
                totalClaimableShares,
                _treeRoot,
                _treeCid
            );
        }

        emit ModuleFeeDistributed(distributed);

        if (rebate > 0) {
            STETH.transferShares(rebateRecipient, rebate);
            emit RebateTransferred(rebate);
        }

        // NOTE: Make sure off-chain tooling provides a distinct CID of a log even for empty reports, e.g. by mixing
        // in a frame identifier such as reference slot to a file.
        if (bytes(_logCid).length == 0) {
            revert InvalidLogCID();
        }
        if (keccak256(bytes(_logCid)) == keccak256(bytes(logCid))) {
            revert InvalidLogCID();
        }

        logCid = _logCid;
        emit DistributionLogUpdated(_logCid);

        _distributionDataHistory[
            distributionDataHistoryCount
        ] = DistributionData({
            refSlot: refSlot,
            treeRoot: treeRoot,
            treeCid: treeCid,
            logCid: _logCid,
            distributed: distributed,
            rebate: rebate
        });

        unchecked {
            ++distributionDataHistoryCount;
        }
    }

    /// @inheritdoc AssetRecoverer
    function recoverERC20(address token, uint256 amount) external override {
        _onlyRecoverer();
        if (token == address(STETH)) {
            revert NotAllowedToRecover();
        }
        AssetRecovererLib.recoverERC20(token, amount);
    }

    /// @inheritdoc IFeeDistributor
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IFeeDistributor
    function pendingSharesToDistribute() external view returns (uint256) {
        return STETH.sharesOf(address(this)) - totalClaimableShares;
    }

    /// @inheritdoc IFeeDistributor
    function getHistoricalDistributionData(
        uint256 index
    ) external view returns (DistributionData memory) {
        return _distributionDataHistory[index];
    }

    /// @inheritdoc IFeeDistributor
    function getFeesToDistribute(
        uint256 nodeOperatorId,
        uint256 cumulativeFeeShares,
        bytes32[] calldata proof
    ) public view returns (uint256 sharesToDistribute) {
        // NOTE: We reject empty proofs to separate two business logic paths on the level of
        // Accounting.sol (see _pullFeeRewards function invocations) with and without a proof.
        if (proof.length == 0) {
            revert InvalidProof();
        }

        bool isValid = MerkleProof.verifyCalldata(
            proof,
            treeRoot,
            hashLeaf(nodeOperatorId, cumulativeFeeShares)
        );
        if (!isValid) {
            revert InvalidProof();
        }

        uint256 _distributedShares = distributedShares[nodeOperatorId];
        if (_distributedShares > cumulativeFeeShares) {
            // This error means the fee oracle brought invalid data.
            revert FeeSharesDecrease();
        }

        unchecked {
            sharesToDistribute = cumulativeFeeShares - _distributedShares;
        }
    }

    /// @inheritdoc IFeeDistributor
    function hashLeaf(
        uint256 nodeOperatorId,
        uint256 shares
    ) public pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(keccak256(abi.encode(nodeOperatorId, shares)))
            );
    }

    function _setRebateRecipient(address _rebateRecipient) internal {
        if (_rebateRecipient == address(0)) {
            revert ZeroRebateRecipientAddress();
        }

        rebateRecipient = _rebateRecipient;
        emit RebateRecipientSet(_rebateRecipient);
    }

    function _onlyAccounting() internal view {
        if (msg.sender != ACCOUNTING) {
            revert SenderIsNotAccounting();
        }
    }

    function _onlyOracle() internal view {
        if (msg.sender != ORACLE) {
            revert SenderIsNotOracle();
        }
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }
}
