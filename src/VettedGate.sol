// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { PausableUntil } from "./lib/utils/PausableUntil.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IMerkleGate } from "./interfaces/IMerkleGate.sol";
import { IVettedGate } from "./interfaces/IVettedGate.sol";

contract VettedGate is
    IVettedGate,
    AccessControlEnumerableUpgradeable,
    PausableUntil,
    AssetRecoverer
{
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");
    bytes32 public constant SET_TREE_ROLE = keccak256("SET_TREE_ROLE");
    bytes32 public constant START_REFERRAL_SEASON_ROLE =
        keccak256("START_REFERRAL_SEASON_ROLE");
    bytes32 public constant END_REFERRAL_SEASON_ROLE =
        keccak256("END_REFERRAL_SEASON_ROLE");

    /// @dev Address of the Staking Module
    IBaseModule public immutable MODULE;

    /// @dev Address of the Accounting
    IAccounting public immutable ACCOUNTING;

    /// @dev Id of the bond curve to be assigned for the eligible members
    uint256 public curveId;

    /// @dev Root of the eligible members Merkle Tree
    bytes32 public treeRoot;

    /// @dev CID of the eligible members Merkle Tree
    string public treeCid;

    mapping(address => bool) internal _consumedAddresses;

    /////////////////////////////////
    /// Optional referral program ///
    /////////////////////////////////

    bool public isReferralProgramSeasonActive;

    uint256 public referralProgramSeasonNumber;

    /// @dev Id of the bond curve for referral program
    uint256 public referralCurveId;

    /// @dev Number of referrals required for bond curve claim
    uint256 public referralsThreshold;

    /// @dev Referral counts for referrers for seasons
    mapping(bytes32 => uint256) internal _referralCounts;

    mapping(bytes32 => bool) internal _consumedReferrers;

    constructor(address module) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }

        MODULE = IBaseModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());

        _disableInitializers();
    }

    function initialize(
        uint256 _curveId,
        bytes32 _treeRoot,
        string calldata _treeCid,
        address admin
    ) external initializer {
        __AccessControlEnumerable_init();

        if (_curveId == ACCOUNTING.DEFAULT_BOND_CURVE_ID()) {
            revert InvalidCurveId();
        }

        // @dev there is no check for curve existence as this contract might be created before the curve is added
        curveId = _curveId;

        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        _setTreeParams(_treeRoot, _treeCid);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IVettedGate
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc IVettedGate
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc IVettedGate
    function startNewReferralProgramSeason(
        uint256 _referralCurveId,
        uint256 _referralsThreshold
    ) external onlyRole(START_REFERRAL_SEASON_ROLE) returns (uint256 season) {
        if (isReferralProgramSeasonActive) {
            revert ReferralProgramIsActive();
        }
        if (_referralCurveId == ACCOUNTING.DEFAULT_BOND_CURVE_ID()) {
            revert InvalidCurveId();
        }
        if (_referralsThreshold == 0) {
            revert InvalidReferralsThreshold();
        }

        referralCurveId = _referralCurveId;
        referralsThreshold = _referralsThreshold;
        isReferralProgramSeasonActive = true;

        season = referralProgramSeasonNumber + 1;
        referralProgramSeasonNumber = season;

        emit ReferralProgramSeasonStarted(
            season,
            _referralCurveId,
            _referralsThreshold
        );
    }

    /// @inheritdoc IVettedGate
    function endCurrentReferralProgramSeason()
        external
        onlyRole(END_REFERRAL_SEASON_ROLE)
    {
        if (
            !isReferralProgramSeasonActive || referralProgramSeasonNumber == 0
        ) {
            revert ReferralProgramIsNotActive();
        }

        isReferralProgramSeasonActive = false;

        emit ReferralProgramSeasonEnded(referralProgramSeasonNumber);
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        bytes32[] calldata proof,
        address referrer
    ) external payable whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysETH{ value: msg.value }({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures
        });

        _bumpReferralCount(referrer, nodeOperatorId);
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorStETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        bytes32[] calldata proof,
        address referrer
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysStETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });

        _bumpReferralCount(referrer, nodeOperatorId);
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorWstETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        bytes32[] calldata proof,
        address referrer
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysWstETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });

        _bumpReferralCount(referrer, nodeOperatorId);
    }

    /// @inheritdoc IVettedGate
    function claimBondCurve(
        uint256 nodeOperatorId,
        bytes32[] calldata proof
    ) external whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        _consume(proof);

        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
    }

    /// @inheritdoc IVettedGate
    function claimReferrerBondCurve(
        uint256 nodeOperatorId,
        bytes32[] calldata proof
    ) external whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        // @dev Only members from the current merkle tree can claim the referral bond curve
        if (!verifyProof(msg.sender, proof)) {
            revert InvalidProof();
        }

        if (!isReferralProgramSeasonActive) {
            revert ReferralProgramIsNotActive();
        }

        uint256 season = referralProgramSeasonNumber;
        bytes32 referrer = _seasonedAddress(msg.sender, season);

        if (_referralCounts[referrer] < referralsThreshold) {
            revert NotEnoughReferrals();
        }

        if (_consumedReferrers[referrer]) {
            revert AlreadyConsumed();
        }

        _consumedReferrers[referrer] = true;

        emit ReferrerConsumed(msg.sender, season);

        ACCOUNTING.setBondCurve(nodeOperatorId, referralCurveId);
    }

    /// @inheritdoc IMerkleGate
    function setTreeParams(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external onlyRole(SET_TREE_ROLE) {
        _setTreeParams(_treeRoot, _treeCid);
    }

    /// @inheritdoc IVettedGate
    function getReferralsCount(
        address referrer
    ) external view returns (uint256) {
        return _referralCounts[_seasonedAddress(referrer)];
    }

    /// @inheritdoc IVettedGate
    function getReferralsCount(
        address referrer,
        uint256 season
    ) external view returns (uint256) {
        return _referralCounts[_seasonedAddress(referrer, season)];
    }

    /// @inheritdoc IMerkleGate
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IVettedGate
    function isReferrerConsumed(address referrer) external view returns (bool) {
        return _consumedReferrers[_seasonedAddress(referrer)];
    }

    /// @inheritdoc IMerkleGate
    function isConsumed(address member) public view returns (bool) {
        return _consumedAddresses[member];
    }

    /// @inheritdoc IMerkleGate
    function verifyProof(
        address member,
        bytes32[] calldata proof
    ) public view returns (bool) {
        return MerkleProof.verifyCalldata(proof, treeRoot, hashLeaf(member));
    }

    /// @inheritdoc IMerkleGate
    function hashLeaf(address member) public pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(member))));
    }

    function _consume(bytes32[] calldata proof) internal {
        if (isConsumed(msg.sender)) {
            revert AlreadyConsumed();
        }

        if (!verifyProof(msg.sender, proof)) {
            revert InvalidProof();
        }

        _consumedAddresses[msg.sender] = true;

        emit Consumed(msg.sender);
    }

    function _setTreeParams(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) internal {
        if (_treeRoot == bytes32(0)) {
            revert InvalidTreeRoot();
        }
        if (_treeRoot == treeRoot) {
            revert InvalidTreeRoot();
        }

        if (bytes(_treeCid).length == 0) {
            revert InvalidTreeCid();
        }
        if (keccak256(bytes(_treeCid)) == keccak256(bytes(treeCid))) {
            revert InvalidTreeCid();
        }

        treeRoot = _treeRoot;
        treeCid = _treeCid;

        emit TreeSet(_treeRoot, _treeCid);
    }

    function _bumpReferralCount(
        address referrer,
        uint256 referralNodeOperatorId
    ) internal {
        uint256 season = referralProgramSeasonNumber;
        if (
            isReferralProgramSeasonActive &&
            referrer != address(0) &&
            referrer != msg.sender
        ) {
            _referralCounts[_seasonedAddress(referrer, season)] += 1;
            emit ReferralRecorded(referrer, season, referralNodeOperatorId);
        }
    }

    function _seasonedAddress(
        address referrer
    ) internal view returns (bytes32) {
        return _seasonedAddress(referrer, referralProgramSeasonNumber);
    }

    /// @dev Verifies that the sender is the owner of the node operator
    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) {
            revert NodeOperatorDoesNotExist();
        }
        if (owner != msg.sender) {
            revert NotAllowedToClaim();
        }
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function _seasonedAddress(
        address referrer,
        uint256 season
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(referrer, season));
    }
}
