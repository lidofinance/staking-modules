// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAccounting } from "./IAccounting.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";
import { IBaseModule } from "./IBaseModule.sol";
import { IExitTypes } from "./IExitTypes.sol";

struct MarkedUint248 {
    uint248 value;
    bool isValue;
}

struct ExitPenaltyInfo {
    MarkedUint248 delayFee;
    MarkedUint248 strikesPenalty;
    MarkedUint248 withdrawalRequestFee;
}

interface IExitPenalties is IExitTypes {
    error ZeroModuleAddress();
    error ZeroParametersRegistryAddress();
    error ZeroStrikesAddress();
    error SenderIsNotModule();
    error SenderIsNotStrikes();
    error ValidatorExitDelayNotApplicable();

    event ValidatorExitDelayProcessed(
        uint256 indexed nodeOperatorId,
        bytes pubkey,
        uint256 delayFee
    );
    event TriggeredExitFeeRecorded(
        uint256 indexed nodeOperatorId,
        uint256 indexed exitType,
        bytes pubkey,
        uint256 withdrawalRequestPaidFee,
        uint256 withdrawalRequestRecordedFee
    );
    event StrikesPenaltyProcessed(
        uint256 indexed nodeOperatorId,
        bytes pubkey,
        uint256 strikesPenalty
    );

    function MODULE() external view returns (IBaseModule);

    function ACCOUNTING() external view returns (IAccounting);

    function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);

    function STRIKES() external view returns (address);

    /// @notice Handles tracking and penalization logic for a validator that remains active beyond its eligible exit window.
    /// @dev see IStakingModule.reportValidatorExitDelay for details
    /// @param nodeOperatorId The ID of the node operator whose validator's status is being delivered.
    /// @param publicKey The public key of the validator being reported.
    /// @param eligibleToExitInSec The duration (in seconds) indicating how long the validator has been eligible to exit but has not exited.
    function processExitDelayReport(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external;

    /// @notice Process the triggered exit report
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    /// @param withdrawalRequestPaidFee The fee paid for the withdrawal request
    /// @param exitType The type of the exit (0 - direct exit, 1 - forced exit)
    function processTriggeredExit(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 withdrawalRequestPaidFee,
        uint256 exitType
    ) external;

    /// @notice Process the strikes report
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    function processStrikesReport(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external;

    /// @notice Determines whether a validator exit status should be updated and will have affect on Node Operator.
    /// @dev called only by the module
    /// @param nodeOperatorId The ID of the node operator.
    /// @param publicKey Validator's public key.
    /// @param eligibleToExitInSec The number of seconds the validator was eligible to exit but did not.
    /// @return bool Returns true if contract should receive updated validator's status.
    function isValidatorExitDelayPenaltyApplicable(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external view returns (bool);

    /// @notice get delayed exit penalty info for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param publicKey Public key of the validator
    /// @return penaltyInfo Delayed exit penalty info
    function getExitPenaltyInfo(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external view returns (ExitPenaltyInfo memory penaltyInfo);
}
