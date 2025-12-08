// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { ICSModule } from "./ICSModule.sol";
import { IAccounting } from "./IAccounting.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";
import { IExitPenalties } from "./IExitPenalties.sol";
import { IEjector } from "./IEjector.sol";

interface IValidatorStrikes {
    /// @dev Emitted when strikes data is updated
    event StrikesDataUpdated(bytes32 treeRoot, string treeCid);
    /// @dev Emitted when strikes is updated from non-empty to empty
    event StrikesDataWiped();
    event EjectorSet(address ejector);

    error ZeroEjectorAddress();
    error ZeroModuleAddress();
    error ZeroOracleAddress();
    error ZeroExitPenaltiesAddress();
    error ZeroParametersRegistryAddress();
    error ZeroAdminAddress();
    error SenderIsNotOracle();
    error ValueNotEvenlyDivisible();
    error EmptyKeyStrikesList();
    error ZeroMsgValue();

    error InvalidReportData();
    error InvalidProof();
    error NotEnoughStrikesToEject();

    struct KeyStrikes {
        uint256 nodeOperatorId;
        uint256 keyIndex;
        uint256[] data;
    }

    function ORACLE() external view returns (address);

    function MODULE() external view returns (ICSModule);

    function ACCOUNTING() external view returns (IAccounting);

    function EXIT_PENALTIES() external view returns (IExitPenalties);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function ejector() external view returns (IEjector);

    function treeRoot() external view returns (bytes32);

    function treeCid() external view returns (string calldata);

    /// @notice Set the address of the Ejector contract
    /// @param _ejector Address of the Ejector contract
    function setEjector(address _ejector) external;

    /// @notice Report multiple keys as bad performing
    /// @param keyStrikesList List of KeyStrikes structs
    /// @param proof Multi-proof of the strikes
    /// @param proofFlags Flags to process the multi-proof, see OZ `processMultiProof`
    /// @param refundRecipient Address to send the refund to
    function processBadPerformanceProof(
        KeyStrikes[] calldata keyStrikesList,
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        address refundRecipient
    ) external payable;

    /// @notice Receive the data of the Merkle tree from the Oracle contract and process it
    /// @param _treeRoot Root of the Merkle tree
    /// @param _treeCid an IPFS CID of the tree
    /// @dev New tree might be empty and it is valid value because of `strikesLifetime`
    function processOracleReport(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external;

    /// @notice Check the contract accepts the provided multi-proof
    /// @param keyStrikesList List of KeyStrikes structs
    /// @param proof Multi-proof of the strikes
    /// @param proofFlags Flags to process the multi-proof, see OZ `processMultiProof`
    /// @return bool True if proof is accepted
    function verifyProof(
        KeyStrikes[] calldata keyStrikesList,
        bytes[] memory pubkeys,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external view returns (bool);

    /// @notice Get a hash of a leaf a tree of strikes
    /// @param keyStrikes KeyStrikes struct
    /// @param pubkey Public key
    /// @return Hash of the leaf
    /// @dev Double hash the leaf to prevent second pre-image attacks
    function hashLeaf(
        KeyStrikes calldata keyStrikes,
        bytes calldata pubkey
    ) external pure returns (bytes32);

    /// @notice Returns the initialized version of the contract
    function getInitializedVersion() external view returns (uint64);
}
