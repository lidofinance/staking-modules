// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IConsensusContract } from "../../../src/lib/base-oracle/interfaces/IConsensusContract.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract MockConsensusContract is IConsensusContract {
    using SafeCast for uint256;

    uint64 internal immutable SLOTS_PER_EPOCH;
    uint64 internal immutable SECONDS_PER_SLOT;
    uint64 internal immutable GENESIS_TIME;

    address internal _reportProcessor;

    mapping(address => uint256) internal _memberIndices1b;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    struct ConsensusFrame {
        uint256 index;
        uint256 refSlot;
        uint256 reportProcessingDeadlineSlot;
    }

    struct FrameConfig {
        uint64 initialEpoch;
        uint64 epochsPerFrame;
        uint64 fastLaneLengthSlots;
    }

    FrameConfig internal _frameConfig;
    ConsensusFrame internal _consensusFrame;
    uint256 internal _initialRefSlot;

    // Test utility variables
    uint256 public lastSetEpochsPerFrame;
    uint256 public lastSetFastLaneLengthSlots;

    constructor(
        uint256 slotsPerEpoch,
        uint256 secondsPerSlot,
        uint256 genesisTime,
        uint256 epochsPerFrame,
        uint256 initialEpoch,
        uint256 fastLaneLengthSlots,
        address mockMember
    ) {
        SLOTS_PER_EPOCH = slotsPerEpoch.toUint64();
        SECONDS_PER_SLOT = secondsPerSlot.toUint64();
        GENESIS_TIME = genesisTime.toUint64();

        _setFrameConfig(initialEpoch, epochsPerFrame, fastLaneLengthSlots);
        _memberIndices1b[mockMember] = 1;

        _consensusFrame.index = 10;
        _consensusFrame.refSlot = 1;
        _consensusFrame.reportProcessingDeadlineSlot = 7001;

        _initialRefSlot = initialEpoch * slotsPerEpoch - 1;
    }

    function getIsMember(address addr) external view returns (bool) {
        return _memberIndices1b[addr] != 0;
    }

    function getCurrentFrame()
        external
        view
        returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot)
    {
        return (
            _consensusFrame.refSlot,
            _consensusFrame.reportProcessingDeadlineSlot
        );
    }

    function setCurrentFrame(
        uint256 index,
        uint256 refSlot,
        uint256 reportProcessingDeadlineSlot
    ) external {
        _consensusFrame.index = index;
        _consensusFrame.refSlot = refSlot;
        _consensusFrame
            .reportProcessingDeadlineSlot = reportProcessingDeadlineSlot;
    }

    function setInitialRefSlot(uint256 initialRefSlot) external {
        _initialRefSlot = initialRefSlot;
    }

    function getChainConfig()
        external
        view
        returns (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        )
    {
        return (SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME);
    }

    function getFrameConfig()
        external
        view
        returns (
            uint256 initialEpoch,
            uint256 epochsPerFrame,
            uint256 fastLaneLengthSlots
        )
    {
        return (
            _frameConfig.initialEpoch,
            _frameConfig.epochsPerFrame,
            _frameConfig.fastLaneLengthSlots
        );
    }

    function getInitialRefSlot() external view returns (uint256) {
        return _initialRefSlot;
    }

    function MANAGE_FRAME_CONFIG_ROLE() external pure returns (bytes32) {
        return keccak256("MANAGE_FRAME_CONFIG_ROLE");
    }

    function setFrameConfig(
        uint256 epochsPerFrame,
        uint256 fastLaneLengthSlots
    ) external {
        _frameConfig.epochsPerFrame = epochsPerFrame.toUint64();
        _frameConfig.fastLaneLengthSlots = fastLaneLengthSlots.toUint64();
        lastSetEpochsPerFrame = epochsPerFrame;
        lastSetFastLaneLengthSlots = fastLaneLengthSlots;
    }

    function resetTestState() external {
        lastSetEpochsPerFrame = 0;
        lastSetFastLaneLengthSlots = 0;
    }

    function _setFrameConfig(
        uint256 initialEpoch,
        uint256 epochsPerFrame,
        uint256 fastLaneLengthSlots
    ) internal {
        _frameConfig = FrameConfig(
            initialEpoch.toUint64(),
            epochsPerFrame.toUint64(),
            fastLaneLengthSlots.toUint64()
        );
    }

    // AccessControl methods for role management
    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function renounceRole(bytes32 role, address account) external {
        require(msg.sender == account, "Can only renounce own role");
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external {
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool) {
        return _roles[role][account];
    }
}
