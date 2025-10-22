// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ExitTypes } from "./abstract/ExitTypes.sol";

import { ICSAccounting } from "./interfaces/ICSAccounting.sol";
import { ICSExitPenalties, MarkedUint248, ExitPenaltyInfo } from "./interfaces/ICSExitPenalties.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";
import { ICSParametersRegistry } from "./interfaces/ICSParametersRegistry.sol";

contract CSExitPenalties is ICSExitPenalties, ExitTypes {
    using SafeCast for uint256;

    ICSModule public immutable MODULE;
    ICSParametersRegistry public immutable PARAMETERS_REGISTRY;
    ICSAccounting public immutable ACCOUNTING;
    address public immutable STRIKES;

    mapping(bytes32 keyPointer => ExitPenaltyInfo) private _exitPenaltyInfo;

    modifier onlyModule() {
        if (msg.sender != address(MODULE)) {
            revert SenderIsNotModule();
        }

        _;
    }

    modifier onlyStrikes() {
        if (msg.sender != STRIKES) {
            revert SenderIsNotStrikes();
        }

        _;
    }

    constructor(address module, address parametersRegistry, address strikes) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }
        if (parametersRegistry == address(0)) {
            revert ZeroParametersRegistryAddress();
        }
        if (strikes == address(0)) {
            revert ZeroStrikesAddress();
        }

        MODULE = ICSModule(module);
        PARAMETERS_REGISTRY = ICSParametersRegistry(parametersRegistry);
        ACCOUNTING = MODULE.accounting();
        STRIKES = strikes;
    }

    /// @inheritdoc ICSExitPenalties
    function processExitDelayReport(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external onlyModule {
        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);

        uint256 allowedExitDelay = PARAMETERS_REGISTRY.getAllowedExitDelay(
            curveId
        );
        if (eligibleToExitInSec <= allowedExitDelay) {
            revert ValidatorExitDelayNotApplicable();
        }

        bytes32 keyPointer = _keyPointer(nodeOperatorId, publicKey);
        ExitPenaltyInfo storage exitPenaltyInfo = _exitPenaltyInfo[keyPointer];
        if (exitPenaltyInfo.delayFee.isValue) {
            return;
        }

        uint256 delayFee = PARAMETERS_REGISTRY.getExitDelayFee(curveId);
        exitPenaltyInfo.delayFee = MarkedUint248(delayFee.toUint248(), true);
        emit ValidatorExitDelayProcessed(nodeOperatorId, publicKey, delayFee);
    }

    /// @inheritdoc ICSExitPenalties
    function processTriggeredExit(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 withdrawalRequestPaidFee,
        uint256 exitType
    ) external onlyModule {
        if (exitType == VOLUNTARY_EXIT_TYPE_ID) {
            return;
        }

        bytes32 keyPointer = _keyPointer(nodeOperatorId, publicKey);
        ExitPenaltyInfo storage exitPenaltyInfo = _exitPenaltyInfo[keyPointer];
        // don't update the fee if it was already set to prevent hypothetical manipulations
        //    with double reporting to get lower/higher fee.
        if (exitPenaltyInfo.withdrawalRequestFee.isValue) {
            return;
        }
        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 maxFee = PARAMETERS_REGISTRY.getMaxWithdrawalRequestFee(
            curveId
        );

        uint256 fee = Math.min(withdrawalRequestPaidFee, maxFee);

        exitPenaltyInfo.withdrawalRequestFee = MarkedUint248(
            fee.toUint248(),
            true
        );
        emit TriggeredExitFeeRecorded({
            nodeOperatorId: nodeOperatorId,
            exitType: exitType,
            pubkey: publicKey,
            withdrawalRequestPaidFee: withdrawalRequestPaidFee,
            withdrawalRequestRecordedFee: fee
        });
    }

    /// @inheritdoc ICSExitPenalties
    function processStrikesReport(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external onlyStrikes {
        bytes32 keyPointer = _keyPointer(nodeOperatorId, publicKey);
        ExitPenaltyInfo storage exitPenaltyInfo = _exitPenaltyInfo[keyPointer];
        if (exitPenaltyInfo.strikesPenalty.isValue) {
            return;
        }

        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 penalty = PARAMETERS_REGISTRY.getBadPerformancePenalty(curveId);
        exitPenaltyInfo.strikesPenalty = MarkedUint248(
            penalty.toUint248(),
            true
        );
        emit StrikesPenaltyProcessed(nodeOperatorId, publicKey, penalty);
    }

    /// @inheritdoc ICSExitPenalties
    /// @dev there is a `onlyModule` modifier to prevent using it from outside
    ///     as it gives a false-positive information for non-existent node operators.
    ///     use `isValidatorExitDelayPenaltyApplicable` in the CSModule.sol instead
    function isValidatorExitDelayPenaltyApplicable(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 eligibleToExitInSec
    ) external view onlyModule returns (bool) {
        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 allowedExitDelay = PARAMETERS_REGISTRY.getAllowedExitDelay(
            curveId
        );
        if (eligibleToExitInSec <= allowedExitDelay) {
            return false;
        }
        bytes32 keyPointer = _keyPointer(nodeOperatorId, publicKey);
        bool isPenaltySet = _exitPenaltyInfo[keyPointer].delayFee.isValue;
        return !isPenaltySet;
    }

    /// @inheritdoc ICSExitPenalties
    function getExitPenaltyInfo(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external view returns (ExitPenaltyInfo memory) {
        bytes32 keyPointer = _keyPointer(nodeOperatorId, publicKey);
        return _exitPenaltyInfo[keyPointer];
    }

    function _keyPointer(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(nodeOperatorId, publicKey));
    }
}
