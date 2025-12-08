// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IBaseModule } from "../../../src/interfaces/IBaseModule.sol";
import { IAccounting } from "../../../src/interfaces/IAccounting.sol";
import { IExitPenalties } from "../../../src/interfaces/IExitPenalties.sol";
import { IParametersRegistry } from "../../../src/interfaces/IParametersRegistry.sol";
import { ExitPenaltyInfo } from "../../../src/interfaces/IExitPenalties.sol";
import { ExitTypes } from "../../../src/abstract/ExitTypes.sol";

contract ExitPenaltiesMock is IExitPenalties, ExitTypes {
    IBaseModule public MODULE;
    IAccounting public ACCOUNTING;
    IParametersRegistry public immutable PARAMETERS_REGISTRY;
    ExitPenaltyInfo internal penaltyInfo;
    bool applicable;

    function STRIKES() external pure returns (address) {
        return address(0);
    }

    function processExitDelayReport(
        uint256,
        bytes calldata,
        uint256
    ) external {}

    function processTriggeredExit(
        uint256,
        bytes calldata,
        uint256,
        uint256
    ) external {}

    function processStrikesReport(
        uint256 nodeOperatorId,
        bytes calldata publicKey
    ) external {}

    function mock_isValidatorExitDelayPenaltyApplicable(bool flag) external {
        applicable = flag;
    }

    function isValidatorExitDelayPenaltyApplicable(
        uint256,
        bytes calldata,
        uint256
    ) external view returns (bool) {
        return applicable;
    }

    function mock_setDelayedExitPenaltyInfo(
        ExitPenaltyInfo memory _penaltyInfo
    ) external {
        penaltyInfo = _penaltyInfo;
    }

    function getExitPenaltyInfo(
        uint256,
        bytes calldata
    ) external view returns (ExitPenaltyInfo memory) {
        return penaltyInfo;
    }

    function getInitializedVersion() external pure returns (uint64) {
        return 1;
    }
}
