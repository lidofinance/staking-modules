// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ExitTypes } from "./abstract/ExitTypes.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IExitPenalties, MarkedUint248, ExitPenaltyInfo } from "./interfaces/IExitPenalties.sol";
import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IParametersRegistry } from "./interfaces/IParametersRegistry.sol";

import { KeyPointerLib } from "./lib/KeyPointerLib.sol";

contract ExitPenalties is IExitPenalties, ExitTypes {
    using SafeCast for uint256;

    IBaseModule public immutable MODULE;
    IParametersRegistry public immutable PARAMETERS_REGISTRY;
    IAccounting public immutable ACCOUNTING;
    address public immutable STRIKES;

    mapping(bytes32 keyPointer => ExitPenaltyInfo info) private _exitPenaltyInfo;

    modifier onlyModule() {
        _onlyModule();
        _;
    }

    modifier onlyStrikes() {
        _onlyStrikes();
        _;
    }

    constructor(address module, address strikes) {
        if (module == address(0)) revert ZeroModuleAddress();
        if (strikes == address(0)) revert ZeroStrikesAddress();

        MODULE = IBaseModule(module);
        PARAMETERS_REGISTRY = MODULE.PARAMETERS_REGISTRY();
        ACCOUNTING = MODULE.ACCOUNTING();
        STRIKES = strikes;
    }

    /// @inheritdoc IExitPenalties
    function processTriggeredExit(
        uint256 nodeOperatorId,
        bytes calldata publicKey,
        uint256 elWithdrawalRequestFeePaid,
        uint256 exitType
    ) external onlyModule {
        if (exitType == VOLUNTARY_EXIT_TYPE_ID) return;

        ExitPenaltyInfo storage exitPenaltyInfo = _exitPenaltyInfo[KeyPointerLib.keyPointer(nodeOperatorId, publicKey)];
        // don't update the fee if it was already set to prevent hypothetical manipulations
        //    with double reporting to get lower/higher fee.
        if (exitPenaltyInfo.elWithdrawalRequestFee.isValue) return;
        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 maxFee = PARAMETERS_REGISTRY.getMaxElWithdrawalRequestFee(curveId);

        uint256 fee = Math.min(elWithdrawalRequestFeePaid, maxFee);

        exitPenaltyInfo.elWithdrawalRequestFee = MarkedUint248(fee.toUint248(), true);
        emit TriggeredExitFeeRecorded({
            nodeOperatorId: nodeOperatorId,
            exitType: exitType,
            pubkey: publicKey,
            withdrawalRequestPaidFee: elWithdrawalRequestFeePaid,
            withdrawalRequestRecordedFee: fee
        });
    }

    /// @inheritdoc IExitPenalties
    function processStrikesReport(uint256 nodeOperatorId, bytes calldata publicKey) external onlyStrikes {
        ExitPenaltyInfo storage exitPenaltyInfo = _exitPenaltyInfo[KeyPointerLib.keyPointer(nodeOperatorId, publicKey)];
        if (exitPenaltyInfo.strikesPenalty.isValue) return;

        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 penalty = PARAMETERS_REGISTRY.getBadPerformancePenalty(curveId);
        exitPenaltyInfo.strikesPenalty = MarkedUint248(penalty.toUint248(), true);
        emit StrikesPenaltyProcessed(nodeOperatorId, publicKey, penalty);
    }

    /// @inheritdoc IExitPenalties
    function getExitPenaltyInfo(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external view returns (ExitPenaltyInfo memory) {
        return _exitPenaltyInfo[KeyPointerLib.keyPointer(nodeOperatorId, publicKey)];
    }

    function _onlyModule() internal view {
        if (msg.sender != address(MODULE)) revert SenderIsNotModule();
    }

    function _onlyStrikes() internal view {
        if (msg.sender != STRIKES) revert SenderIsNotStrikes();
    }
}
