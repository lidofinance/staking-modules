// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IWithdrawalVault } from "../../../src/interfaces/IWithdrawalVault.sol";

import { Test } from "forge-std/Test.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { IStakingModule } from "../../../src/interfaces/IStakingModule.sol";
import { IWithdrawalVault } from "../../../src/interfaces/IWithdrawalVault.sol";
import { Utilities } from "../../helpers/Utilities.sol";

contract EjectionTest is Test, Utilities, DeploymentFixtures {
    uint256 internal nodeOperatorId;

    uint256 internal immutable KEYS_COUNT;

    constructor() {
        KEYS_COUNT = 1;
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        if (module.isPaused()) {
            module.resume();
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
            KEYS_COUNT
        );

        uint256 initialBalance = 1 ether;
        address operatorOwner = module.getNodeOperatorOwner(nodeOperatorId);
        vm.deal(operatorOwner, initialBalance);
        uint256 expectedFee = IWithdrawalVault(locator.withdrawalVault())
            .getWithdrawalRequestFee();

        uint256 VOLUNTARY_EXIT_TYPE_ID = ejector.VOLUNTARY_EXIT_TYPE_ID();
        address withdrawalVault = locator.withdrawalVault();
        bytes[] memory pubkeys = new bytes[](KEYS_COUNT);

        for (uint256 i = 0; i < KEYS_COUNT; i++) {
            pubkeys[i] = module.getSigningKeys(
                nodeOperatorId,
                startFrom + i,
                1
            );
        }
        for (uint256 i = 0; i < KEYS_COUNT; i++) {
            vm.expectEmit(withdrawalVault);
            emit IWithdrawalVault.WithdrawalRequestAdded(
                _prepareWithdrawalRequestData(pubkeys[i])
            );
            vm.expectCall(
                address(module),
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
            KEYS_COUNT,
            operatorOwner
        );
        vm.stopSnapshotGas();

        vm.assertEq(
            operatorOwner.balance,
            initialBalance - expectedFee * KEYS_COUNT
        );
    }

    function test_voluntaryEjectByArray() public {
        nodeOperatorId = getDepositedNodeOperator(nextAddress(), KEYS_COUNT);

        uint256 initialBalance = 1 ether;
        address operatorOwner = module.getNodeOperatorOwner(nodeOperatorId);
        vm.deal(operatorOwner, initialBalance);
        uint256 expectedFee = IWithdrawalVault(locator.withdrawalVault())
            .getWithdrawalRequestFee();

        uint256 VOLUNTARY_EXIT_TYPE_ID = ejector.VOLUNTARY_EXIT_TYPE_ID();
        address withdrawalVault = locator.withdrawalVault();
        bytes[] memory pubkeys = new bytes[](KEYS_COUNT);
        uint256[] memory keyIds = new uint256[](KEYS_COUNT);

        {
            uint256 i;
            uint256 keyIndex;
            while (i < KEYS_COUNT) {
                if (module.isValidatorWithdrawn(nodeOperatorId, keyIndex)) {
                    keyIndex++;
                    continue;
                }
                keyIds[i] = keyIndex;
                pubkeys[i] = module.getSigningKeys(nodeOperatorId, keyIndex, 1);
                i++;
                keyIndex++;
            }
        }

        for (uint256 i = 0; i < KEYS_COUNT; i++) {
            vm.expectEmit(withdrawalVault);
            emit IWithdrawalVault.WithdrawalRequestAdded(
                _prepareWithdrawalRequestData(pubkeys[i])
            );
            vm.expectCall(
                address(module),
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
            initialBalance - expectedFee * KEYS_COUNT
        );
    }
}

contract EjectionTest10Keys is EjectionTest {
    constructor() {
        KEYS_COUNT = 10;
    }
}
