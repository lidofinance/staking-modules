// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

interface IConsensusContract {
    function getIsMember(address addr) external view returns (bool);

    function getCurrentFrame()
        external
        view
        returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);

    function getChainConfig()
        external
        view
        returns (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        );

    function getInitialRefSlot() external view returns (uint256);

    function setFrameConfig(
        uint256 epochsPerFrame,
        uint256 fastLaneLengthSlots
    ) external;
}
