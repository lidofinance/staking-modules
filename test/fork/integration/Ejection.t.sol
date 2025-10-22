// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "../../../src/interfaces/IWithdrawalVault.sol";

import "forge-std/Test.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { IStakingModule } from "../../../src/interfaces/IStakingModule.sol";
import { ITriggerableWithdrawalsGateway } from "../../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { IWithdrawalVault } from "../../../src/interfaces/IWithdrawalVault.sol";
import { NodeOperatorManagementProperties } from "../../../src/interfaces/ICSModule.sol";
import { Utilities } from "../../helpers/Utilities.sol";

contract EjectionTest is Test, Utilities, DeploymentFixtures {
    uint256 internal nodeOperatorId;

    uint256 internal immutable keysCount;

    constructor() {
        keysCount = 1;
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        if (csm.isPaused()) {
            csm.resume();
        }
    }

    function _prepareWithdrawalRequestData(
        bytes memory pubkey
    ) internal pure returns (bytes memory request) {
        request = new bytes(56); // 48 bytes for pubkey + 8 bytes for amount (0)
        assembly {
            let requestPtr := add(request, 0x20)
            let pubkeyPtr := add(pubkey, 0x20)
            mstore(requestPtr, mload(pubkeyPtr))
            mstore(add(requestPtr, 0x20), mload(add(pubkeyPtr, 0x20)))
        }
    }

    function test_voluntaryEject() public {
        uint256 startFrom;
        (
            nodeOperatorId,
            startFrom
        ) = getDepositedNodeOperatorWithSequentialActiveKeys(
            nextAddress(),
            keysCount
        );

        uint256 initialBalance = 1 ether;
        address operatorOwner = csm.getNodeOperatorOwner(nodeOperatorId);
        vm.deal(operatorOwner, initialBalance);
        uint256 expectedFee = IWithdrawalVault(locator.withdrawalVault())
            .getWithdrawalRequestFee();

        uint256 VOLUNTARY_EXIT_TYPE_ID = ejector.VOLUNTARY_EXIT_TYPE_ID();
        address withdrawalVault = locator.withdrawalVault();
        bytes[] memory pubkeys = new bytes[](keysCount);

        for (uint256 i = 0; i < keysCount; i++) {
            pubkeys[i] = csm.getSigningKeys(nodeOperatorId, startFrom + i, 1);
        }
        for (uint256 i = 0; i < keysCount; i++) {
            vm.expectEmit(withdrawalVault);
            emit IWithdrawalVault.WithdrawalRequestAdded(
                _prepareWithdrawalRequestData(pubkeys[i])
            );
            vm.expectCall(
                address(csm),
                abi.encodeWithSelector(
                    IStakingModule.onValidatorExitTriggered.selector,
                    nodeOperatorId,
                    pubkeys[i],
                    expectedFee,
                    VOLUNTARY_EXIT_TYPE_ID
                )
            );
        }

        vm.prank(operatorOwner);
        vm.startSnapshotGas("Ejector.voluntaryEject");
        ejector.voluntaryEject{ value: initialBalance }(
            nodeOperatorId,
            startFrom,
            keysCount,
            operatorOwner
        );
        vm.stopSnapshotGas();

        vm.assertEq(
            operatorOwner.balance,
            initialBalance - expectedFee * keysCount
        );
    }

    function test_voluntaryEjectByArray() public {
        nodeOperatorId = getDepositedNodeOperator(nextAddress(), keysCount);

        uint256 initialBalance = 1 ether;
        address operatorOwner = csm.getNodeOperatorOwner(nodeOperatorId);
        vm.deal(operatorOwner, initialBalance);
        uint256 expectedFee = IWithdrawalVault(locator.withdrawalVault())
            .getWithdrawalRequestFee();

        uint256 VOLUNTARY_EXIT_TYPE_ID = ejector.VOLUNTARY_EXIT_TYPE_ID();
        address withdrawalVault = locator.withdrawalVault();
        bytes[] memory pubkeys = new bytes[](keysCount);
        uint256[] memory keyIds = new uint256[](keysCount);

        {
            uint256 i;
            uint256 keyIndex;
            while (i < keysCount) {
                if (csm.isValidatorWithdrawn(nodeOperatorId, keyIndex)) {
                    keyIndex++;
                    continue;
                }
                keyIds[i] = keyIndex;
                pubkeys[i] = csm.getSigningKeys(nodeOperatorId, keyIndex, 1);
                i++;
                keyIndex++;
            }
        }

        for (uint256 i = 0; i < keysCount; i++) {
            vm.expectEmit(withdrawalVault);
            emit IWithdrawalVault.WithdrawalRequestAdded(
                _prepareWithdrawalRequestData(pubkeys[i])
            );
            vm.expectCall(
                address(csm),
                abi.encodeWithSelector(
                    IStakingModule.onValidatorExitTriggered.selector,
                    nodeOperatorId,
                    pubkeys[i],
                    expectedFee,
                    VOLUNTARY_EXIT_TYPE_ID
                )
            );
        }
        vm.prank(operatorOwner);
        vm.startSnapshotGas("Ejector.voluntaryEjectByArray");
        ejector.voluntaryEjectByArray{ value: initialBalance }(
            nodeOperatorId,
            keyIds,
            operatorOwner
        );
        vm.stopSnapshotGas();

        vm.assertEq(
            operatorOwner.balance,
            initialBalance - expectedFee * keysCount
        );
    }
}

contract EjectionTest10Keys is EjectionTest {
    constructor() {
        keysCount = 10;
    }
}
