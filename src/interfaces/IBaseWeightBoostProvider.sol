// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./ICuratedModule.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @notice Module wiring and Node Operator checks shared by the weight boost providers.
interface IBaseWeightBoostProvider is IWeightBoostProvider {
    error ZeroModuleAddress();
    error ZeroAdminAddress();
    error NodeOperatorDoesNotExist();
    error SenderIsNotNodeOperatorOwner();

    /// @notice Curated module the provider serves; its MetaRegistry consumes the weight boost.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Returns the initialized version of the contract.
    function getInitializedVersion() external view returns (uint64);
}
