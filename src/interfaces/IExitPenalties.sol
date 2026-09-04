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
    MarkedUint248 elWithdrawalRequestFee;
}

interface IExitPenalties is IExitTypes {
    error ZeroModuleAddress();
    error ZeroStrikesAddress();
    error SenderIsNotModule();
    error SenderIsNotStrikes();

    event TriggeredExitFeeRecorded(
        uint256 indexed nodeOperatorId,
        uint256 indexed exitType,
        bytes pubkey,
        uint256 withdrawalRequestPaidFee,
        uint256 withdrawalRequestRecordedFee
    );
    event StrikesPenaltyProcessed(uint256 indexed nodeOperatorId, bytes pubkey, uint256 strikesPenalty);

    function MODULE() external view returns (IBaseModule);

    function ACCOUNTING() external view returns (IAccounting);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function STRIKES() external view returns (address);

    /// @notice Process the triggered exit report
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    /// @param elWithdrawalRequestFeePaid The fee paid for the withdrawal request
    /// @param exitType The type of the exit; only `VOLUNTARY_EXIT_TYPE_ID` skips recording EL withdrawal request fee
    function processTriggeredExit(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 elWithdrawalRequestFeePaid,
        uint256 exitType
    ) external;

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
