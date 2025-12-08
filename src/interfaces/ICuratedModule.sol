// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IBaseModule } from "./IBaseModule.sol";
import { IStakingModuleV2 } from "./IStakingModule.sol";

interface ICuratedModule is IBaseModule, IStakingModuleV2 {
    error NotImplemented();

    function OPERATOR_ADDRESSES_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Change both reward and manager addresses of a node operator.
    /// @param nodeOperatorId ID of the Node Operator
    /// @param newManagerAddress New manager address
    /// @param newRewardAddress New reward address
    function changeNodeOperatorAddresses(
        uint256 nodeOperatorId,
        address newManagerAddress,
        address newRewardAddress
    ) external;

    /// @notice  Method to get list of operators and amount of Eth that can be topped up to operator from depositAmount
    /// @param depositAmount Amount of Eth that can be deposited to module
    function getDepositsAllocation(
        uint256 depositAmount
    )
        external
        view
        returns (
            uint256 allocated,
            uint256[] memory operatorIds,
            uint256[] memory allocations
        );
}
