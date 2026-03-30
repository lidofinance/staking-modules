// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { BaseModule } from "src/abstract/BaseModule.sol";
import { NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { AccountingMock } from "../../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../../helpers/mocks/ExitPenaltiesMock.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { Stub } from "../../helpers/mocks/Stub.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";

abstract contract ModuleFixtures is Test, Fixtures, Utilities, InvariantAsserts {
    enum ModuleType {
        Community,
        Curated
    }

    struct BatchInfo {
        uint256 nodeOperatorId;
        uint256 count;
    }

    uint256 public constant BOND_SIZE = 2 ether;
    uint256 internal constant KEYS_UPLOAD_BATCH = 50;

    LidoLocatorMock public locator;
    WstETHMock public wstETH;
    LidoMock public stETH;
    BaseModule public module;
    AccountingMock public accounting;
    Stub public feeDistributor;
    ParametersRegistryMock public parametersRegistry;
    ExitPenaltiesMock public exitPenalties;

    address internal actor;
    address internal admin;
    address internal stranger;
    address internal strangerNumberTwo;
    address internal nodeOperator;
    address internal testChargePenaltyRecipient;
    address internal stakingRouter;

    uint32 internal REGULAR_QUEUE;
    uint32 constant PRIORITY_QUEUE = 0;

    struct NodeOperatorSummary {
        uint256 targetLimitMode;
        uint256 targetValidatorsCount;
        uint256 stuckValidatorsCount;
        uint256 refundedValidatorsCount;
        uint256 stuckPenaltyEndTimestamp;
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    struct StakingModuleSummary {
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        _moduleInvariants();
        vm.resumeGasMetering();
    }

    // TODO: Consider ditching the function override and use moduleType instead.
    function _moduleInvariants() internal virtual;

    function moduleType() internal pure virtual returns (ModuleType);

    function createNodeOperator() internal returns (uint256) {
        return createNodeOperator(nodeOperator, 1);
    }

    function createNodeOperator(uint256 keysCount) internal returns (uint256) {
        return createNodeOperator(nodeOperator, keysCount);
    }

    function createNodeOperator(bool extendedManagerPermissions) internal returns (uint256) {
        return createNodeOperator(nodeOperator, extendedManagerPermissions);
    }

    function createNodeOperator(address managerAddress, uint256 keysCount) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        if (keysCount > 0) uploadMoreKeys(nodeOperatorId, keysCount);
    }

    function createNodeOperator(
        address managerAddress,
        uint256 keysCount,
        bytes memory keys,
        bytes memory signatures
    ) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        uploadMoreKeys(nodeOperatorId, keysCount, keys, signatures);
    }

    function createNodeOperator(address managerAddress, bool extendedManagerPermissions) internal returns (uint256) {
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function createNodeOperator(
        address managerAddress,
        address rewardAddress,
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        vm.prank(module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0));
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: managerAddress,
                    rewardAddress: rewardAddress,
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function _toUint248(uint256 value) internal pure returns (uint248) {
        // All penalty/fee figures come from BOND_SIZE (2 ether) so uint248 is ample.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint248(value);
    }

    function uploadMoreKeys(uint256 noId, uint256 keysCount, bytes memory keys, bytes memory signatures) internal {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        address managerAddress = module.getNodeOperator(noId).managerAddress;
        vm.deal(managerAddress, amount);
        vm.prank(managerAddress);
        module.addValidatorKeysETH{ value: amount }(managerAddress, noId, keysCount, keys, signatures);
    }

    function uploadMoreKeys(uint256 noId, uint256 keysCount) internal {
        uint256 remaining = keysCount;
        uint256 startIndex;

        while (remaining > 0) {
            uint256 batch = remaining > KEYS_UPLOAD_BATCH ? KEYS_UPLOAD_BATCH : remaining;
            (bytes memory keys, bytes memory signatures) = keysSignatures(batch, startIndex);
            uploadMoreKeys(noId, batch, keys, signatures);
            remaining -= batch;
            startIndex += batch;
        }
    }

    function unvetKeys(uint256 noId, uint256 to) internal {
        module.decreaseVettedSigningKeysCount(_encodeNodeOperatorId(noId), _encodeUint128Value(to));
    }

    function setExited(uint256 noId, uint256 to) internal {
        module.updateExitedValidatorsCount(_encodeNodeOperatorId(noId), _encodeUint128Value(to));
    }

    function withdrawKey(uint256 noId, uint256 /* keyIndex */) internal {
        WithdrawnValidatorInfo[] memory withdrawalsInfo = new WithdrawnValidatorInfo[](1);
        withdrawalsInfo[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        module.reportRegularWithdrawnValidators(withdrawalsInfo);
    }

    /// @dev Sets keyConfirmedBalance via reportValidatorBalance.
    function setKeyConfirmedBalance(uint256 noId, uint256 keyIndex, uint256 confirmedBalance) internal {
        uint256 current = module.getKeyConfirmedBalances(noId, keyIndex, 1)[0];
        if (confirmedBalance == current) return;

        assertGt(confirmedBalance, current, "key confirmed balance cannot be decreased");

        module.reportValidatorBalance({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            currentBalanceWei: confirmedBalance + ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        assertEq(
            module.getKeyConfirmedBalances(noId, keyIndex, 1)[0],
            confirmedBalance,
            "key confirmed balance must match target"
        );
    }

    function getNodeOperatorSummary(uint256 noId) public view returns (NodeOperatorSummary memory) {
        (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getNodeOperatorSummary(noId);
        return
            NodeOperatorSummary({
                targetLimitMode: targetLimitMode,
                targetValidatorsCount: targetValidatorsCount,
                stuckValidatorsCount: stuckValidatorsCount,
                refundedValidatorsCount: refundedValidatorsCount,
                stuckPenaltyEndTimestamp: stuckPenaltyEndTimestamp,
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function getStakingModuleSummary() public view returns (StakingModuleSummary memory) {
        (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module
            .getStakingModuleSummary();
        return
            StakingModuleSummary({
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function penalize(uint256 noId, uint256 amount) public {
        vm.prank(address(module));
        accounting.penalize(noId, amount);
        module.updateDepositableValidatorsCount(noId);
    }

    function addBond(uint256 nodeOperatorId, uint256 amount) internal {
        vm.deal(address(module), amount);
        vm.prank(address(module));
        accounting.depositETH{ value: amount }(nodeOperatorId);
    }
}
