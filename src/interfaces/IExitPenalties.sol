// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";
import { IBaseModule } from "./IBaseModule.sol";
import { IExitTypes } from "./IExitTypes.sol";

struct MarkedUint248 {
    uint248 value;
    bool isValue;
}

struct ExitPenaltyInfo {
    /// @dev DEPRECATED. DO NOT USE. Preserves storage layout.
    MarkedUint248 legacyDelayFee;
    MarkedUint248 strikesPenalty;
    /// @dev DEPRECATED. DO NOT USE. Preserves storage layout.
    MarkedUint248 legacyElWithdrawalRequestFee;
}

interface IExitPenalties is IExitTypes {
    error ZeroModuleAddress();
    error ZeroStrikesAddress();
    error SenderIsNotStrikes();

    event StrikesPenaltyProcessed(uint256 indexed nodeOperatorId, bytes pubkey, uint256 strikesPenalty);

    function MODULE() external view returns (IBaseModule);

    function ACCOUNTING() external view returns (IAccounting);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function STRIKES() external view returns (address);

    /// @notice Process the strikes report
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    function processStrikesReport(uint256 nodeOperatorId, bytes calldata publicKey) external;

    /// @notice Get exit penalty info for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    /// @return penaltyInfo Exit penalty info
    function getExitPenaltyInfo(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external view returns (ExitPenaltyInfo memory penaltyInfo);
}
