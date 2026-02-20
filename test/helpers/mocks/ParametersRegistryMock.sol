// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IParametersRegistry } from "../../../src/interfaces/IParametersRegistry.sol";

struct MarkedQueueConfig {
    uint32 priority;
    uint32 maxDeposits;
    bool isValue;
}

contract ParametersRegistryMock {
    uint256 public keyRemovalCharge = 0.01 ether;
    uint256 public additionalFine = 0.1 ether;

    uint256 public keysLimit = 100_000;

    uint256 public strikesLifetime = 6;
    uint256 public strikesThreshold = 3;

    uint256 public badPerformancePenalty = 0.01 ether;

    uint256 public QUEUE_LOWEST_PRIORITY;

    function setQueueLowestPriority(uint256 value) external {
        require(value <= type(uint32).max, "value exceeds uint32");
        QUEUE_LOWEST_PRIORITY = value;
    }

    uint256 public allowedExitDelay = 1 weeks;
    uint256 public exitDelayFee = 0.1 ether;
    uint256 public maxElWithdrawalRequestFee = 1 ether;

    mapping(uint256 curveId => MarkedQueueConfig) internal _queueConfigs;

    function getKeyRemovalCharge(uint256 /* curveId */) external view returns (uint256) {
        return keyRemovalCharge;
    }

    function setKeyRemovalCharge(uint256 /* curveId */, uint256 charge) external {
        keyRemovalCharge = charge;
    }

    function getKeysLimit(uint256 /* curveId */) external view returns (uint256) {
        return keysLimit;
    }

    function setKeysLimit(uint256 /* curveId */, uint256 limit) external {
        keysLimit = limit;
    }

    function setGeneralDelayedPenaltyAdditionalFine(uint256 /* curveId */, uint256 fine) external {
        additionalFine = fine;
    }

    function getGeneralDelayedPenaltyAdditionalFine(uint256 /* curveId */) external view returns (uint256) {
        return additionalFine;
    }

    function getStrikesParams(uint256 /* curveId */) external view returns (uint256, uint256) {
        return (strikesLifetime, strikesThreshold);
    }

    function setStrikesParams(uint256 /* curveId */, uint256 lifetime, uint256 threshold) external {
        strikesLifetime = lifetime;
        strikesThreshold = threshold;
    }

    function getBadPerformancePenalty(uint256 /* curveId */) external view returns (uint256) {
        return badPerformancePenalty;
    }

    function setBadPerformancePenalty(uint256 /* curveId */, uint256 penalty) external {
        badPerformancePenalty = penalty;
    }

    function setQueueConfig(uint256 curveId, uint256 priority, uint256 maxDeposits) external {
        _queueConfigs[curveId] = MarkedQueueConfig({
            // Both values are tiny in tests (priority <= QUEUE_LOWEST_PRIORITY, maxDeposits <= keysLimit < 2^32), so the truncating cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            priority: uint32(priority),
            // forge-lint: disable-next-line(unsafe-typecast)
            maxDeposits: uint32(maxDeposits),
            isValue: true
        });
    }

    function setRewardShareData(uint256, IParametersRegistry.KeyNumberValueInterval[] calldata) external {}

    function setPerformanceLeewayData(uint256, IParametersRegistry.KeyNumberValueInterval[] calldata) external {}

    function getQueueConfig(uint256 curveId) external view returns (uint32 priority, uint32 maxDeposits) {
        MarkedQueueConfig storage config = _queueConfigs[curveId];

        if (!config.isValue) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return (uint32(QUEUE_LOWEST_PRIORITY), type(uint32).max);
        }

        return (config.priority, config.maxDeposits);
    }

    function getAllowedExitDelay(uint256 /* curveId */) external view returns (uint256) {
        return allowedExitDelay;
    }

    function setAllowedExitDelay(uint256, uint256 delay) external {
        allowedExitDelay = delay;
    }

    function getExitDelayFee(uint256 /* curveId */) external view returns (uint256) {
        return exitDelayFee;
    }

    function setExitDelayFee(uint256 /* curveId */, uint256 fee) external {
        exitDelayFee = fee;
    }

    function getMaxElWithdrawalRequestFee(uint256 /* curveId */) external view returns (uint256) {
        return maxElWithdrawalRequestFee;
    }

    function setMaxElWithdrawalRequestFee(uint256 /* curveId */, uint256 _maxElWithdrawalRequestFee) external {
        maxElWithdrawalRequestFee = _maxElWithdrawalRequestFee;
    }

    function setPerformanceCoefficients(uint256, uint256, uint256, uint256) external {}
}
