// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { ICSModule } from "./interfaces/ICSModule.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IExitPenalties } from "./interfaces/IExitPenalties.sol";
import { IParametersRegistry } from "./interfaces/IParametersRegistry.sol";
import { IEjector } from "./interfaces/IEjector.sol";
import { IValidatorStrikes } from "./interfaces/IValidatorStrikes.sol";

/// @author vgorkavenko
contract ValidatorStrikes is
    IValidatorStrikes,
    Initializable,
    AccessControlEnumerableUpgradeable
{
    address public immutable ORACLE;
    ICSModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IExitPenalties public immutable EXIT_PENALTIES;
    IParametersRegistry public immutable PARAMETERS_REGISTRY;

    IEjector public ejector;

    /// @notice The latest Merkle Tree root
    bytes32 public treeRoot;

    /// @notice CID of the last published Merkle tree
    string public treeCid;

    modifier onlyOracle() {
        _onlyOracle();
        _;
    }

    constructor(
        address module,
        address oracle,
        address exitPenalties,
        address parametersRegistry
    ) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }
        if (oracle == address(0)) {
            revert ZeroOracleAddress();
        }
        if (exitPenalties == address(0)) {
            revert ZeroExitPenaltiesAddress();
        }
        if (parametersRegistry == address(0)) {
            revert ZeroParametersRegistryAddress();
        }

        MODULE = ICSModule(module);
        ACCOUNTING = MODULE.ACCOUNTING();
        EXIT_PENALTIES = IExitPenalties(exitPenalties);
        ORACLE = oracle;
        PARAMETERS_REGISTRY = IParametersRegistry(parametersRegistry);

        _disableInitializers();
    }

    function initialize(address admin, address _ejector) external initializer {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        _setEjector(_ejector);

        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IValidatorStrikes
    function setEjector(
        address _ejector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setEjector(_ejector);
    }

    /// @inheritdoc IValidatorStrikes
    function processOracleReport(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external onlyOracle {
        // @dev should be both empty or not empty
        bool isNewRootEmpty = _treeRoot == bytes32(0);
        bool isNewCidEmpty = bytes(_treeCid).length == 0;
        if (isNewRootEmpty != isNewCidEmpty) {
            revert InvalidReportData();
        }

        if (isNewRootEmpty) {
            if (treeRoot != bytes32(0)) {
                delete treeRoot;
                delete treeCid;
                emit StrikesDataWiped();
            }
            return;
        }

        bool isSameRoot = _treeRoot == treeRoot;
        bool isSameCid = keccak256(bytes(_treeCid)) ==
            keccak256(bytes(treeCid));
        if (isSameRoot != isSameCid) {
            revert InvalidReportData();
        }

        if (!isSameRoot) {
            treeRoot = _treeRoot;
            treeCid = _treeCid;
            emit StrikesDataUpdated(_treeRoot, _treeCid);
        }
    }

    /// @inheritdoc IValidatorStrikes
    function processBadPerformanceProof(
        KeyStrikes[] calldata keyStrikesList,
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        address refundRecipient
    ) external payable {
        // NOTE: We allow empty proofs to be delivered because there’s no way to use the tree’s
        // internal nodes without brute-forcing the input data.

        if (keyStrikesList.length == 0) {
            revert EmptyKeyStrikesList();
        }

        if (msg.value == 0) {
            revert ZeroMsgValue();
        }

        if (msg.value % keyStrikesList.length > 0) {
            revert ValueNotEvenlyDivisible();
        }

        bytes[] memory pubkeys = new bytes[](keyStrikesList.length);
        for (uint256 i; i < pubkeys.length; ++i) {
            pubkeys[i] = MODULE.getSigningKeys(
                keyStrikesList[i].nodeOperatorId,
                keyStrikesList[i].keyIndex,
                1
            );
        }

        if (!verifyProof(keyStrikesList, pubkeys, proof, proofFlags)) {
            revert InvalidProof();
        }

        refundRecipient = refundRecipient == address(0)
            ? msg.sender
            : refundRecipient;

        uint256 valuePerKey = msg.value / keyStrikesList.length;
        for (uint256 i; i < keyStrikesList.length; ++i) {
            _ejectByStrikes(
                keyStrikesList[i],
                pubkeys[i],
                valuePerKey,
                refundRecipient
            );
        }
    }

    /// @inheritdoc IValidatorStrikes
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IValidatorStrikes
    function verifyProof(
        KeyStrikes[] calldata keyStrikesList,
        bytes[] memory pubkeys,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) public view returns (bool) {
        bytes32[] memory leaves = new bytes32[](keyStrikesList.length);
        for (uint256 i; i < leaves.length; i++) {
            leaves[i] = hashLeaf(keyStrikesList[i], pubkeys[i]);
        }

        return
            MerkleProof.multiProofVerifyCalldata(
                proof,
                proofFlags,
                treeRoot,
                leaves
            );
    }

    /// @inheritdoc IValidatorStrikes
    function hashLeaf(
        KeyStrikes calldata keyStrikes,
        bytes memory pubkey
    ) public pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(
                    keccak256(
                        abi.encode(
                            keyStrikes.nodeOperatorId,
                            pubkey,
                            keyStrikes.data
                        )
                    )
                )
            );
    }

    function _setEjector(address _ejector) internal {
        if (_ejector == address(0)) {
            revert ZeroEjectorAddress();
        }
        ejector = IEjector(_ejector);
        emit EjectorSet(_ejector);
    }

    function _ejectByStrikes(
        KeyStrikes calldata keyStrikes,
        bytes memory pubkey,
        uint256 value,
        address refundRecipient
    ) internal {
        uint256 strikes = 0;
        for (uint256 i; i < keyStrikes.data.length; ++i) {
            strikes += keyStrikes.data[i];
        }

        uint256 curveId = ACCOUNTING.getBondCurveId(keyStrikes.nodeOperatorId);

        (, uint256 threshold) = PARAMETERS_REGISTRY.getStrikesParams(curveId);
        if (strikes < threshold) {
            revert NotEnoughStrikesToEject();
        }

        EXIT_PENALTIES.processStrikesReport(keyStrikes.nodeOperatorId, pubkey);

        ejector.ejectBadPerformer{ value: value }(
            keyStrikes.nodeOperatorId,
            keyStrikes.keyIndex,
            refundRecipient
        );
    }

    function _onlyOracle() internal view {
        if (msg.sender != ORACLE) {
            revert SenderIsNotOracle();
        }
    }
}
