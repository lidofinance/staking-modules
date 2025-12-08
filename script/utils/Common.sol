// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IParametersRegistry } from "../../src/interfaces/IParametersRegistry.sol";
import { IBondCurve } from "../../src/interfaces/IBondCurve.sol";

library CommonScriptUtils {
    function arraysToKeyIndexValueIntervals(
        uint256[2][] memory data
    )
        internal
        pure
        returns (IParametersRegistry.KeyNumberValueInterval[] memory)
    {
        IParametersRegistry.KeyNumberValueInterval[]
            memory keyIndexValues = new IParametersRegistry.KeyNumberValueInterval[](
                data.length
            );
        for (uint256 i = 0; i < data.length; i++) {
            keyIndexValues[i] = IParametersRegistry.KeyNumberValueInterval({
                minKeyNumber: data[i][0],
                value: data[i][1]
            });
        }
        return keyIndexValues;
    }

    function arraysToBondCurveIntervalsInputs(
        uint256[2][] memory data
    ) internal pure returns (IBondCurve.BondCurveIntervalInput[] memory) {
        IBondCurve.BondCurveIntervalInput[]
            memory bondCurveInputs = new IBondCurve.BondCurveIntervalInput[](
                data.length
            );
        for (uint256 i = 0; i < data.length; i++) {
            bondCurveInputs[i] = IBondCurve.BondCurveIntervalInput({
                minKeysCount: data[i][0],
                trend: data[i][1]
            });
        }
        return bondCurveInputs;
    }
}
