// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStakingModule } from "../../../../src/interfaces/IStakingModule.sol";
import { IStakingRouter } from "../../../../src/interfaces/IStakingRouter.sol";
import { IWithdrawalVault } from "../../../../src/interfaces/IWithdrawalVault.sol";
import { IEjector } from "../../../../src/interfaces/IEjector.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract EjectionTestBase is ModuleTypeBase {
    uint256 internal nodeOperatorId;

    uint256 internal immutable KEYS_COUNT;

    constructor() {
        KEYS_COUNT = 1;
    }

    function setUp() public {
        _setUpModule();

        if (module.isPaused()) module.resume();
    }

    function _prepareWithdrawalRequestData(bytes memory pubkey) internal pure returns (bytes memory request) {
        request = new bytes(56); // 48 bytes for pubkey + 8 bytes for amount (0)
        assembly {
            let requestPtr := add(request, 0x20)
            let pubkeyPtr := add(pubkey, 0x20)
            mstore(requestPtr, mload(pubkeyPtr))
            mstore(add(requestPtr, 0x20), mload(add(pubkeyPtr, 0x20)))
        }
    }

    function test_voluntaryEject() public {
        nodeOperatorId = integrationHelpers.getDepositedNodeOperator(nextAddress(), KEYS_COUNT);

        uint256 initialBalance = 1 ether;
        address operatorOwner = module.getNodeOperatorOwner(nodeOperatorId);
        vm.deal(operatorOwner, initialBalance);
        uint256 expectedFee = IWithdrawalVault(locator.withdrawalVault()).getWithdrawalRequestFee();

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
            vm.expectEmit(address(ejector));
            emit IEjector.VoluntaryEjectionRequested({
                nodeOperatorId: nodeOperatorId,
                pubkey: pubkeys[i],
                refundRecipient: operatorOwner
            });
        }
        for (uint256 i = 0; i < KEYS_COUNT; i++) {
            vm.expectEmit(withdrawalVault);
            emit IWithdrawalVault.WithdrawalRequestAdded(_prepareWithdrawalRequestData(pubkeys[i]));
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
        vm.startSnapshotGas("ejector.voluntaryEject");
        ejector.voluntaryEject{ value: initialBalance }(nodeOperatorId, keyIds, operatorOwner);
        vm.stopSnapshotGas();

        vm.assertEq(operatorOwner.balance, initialBalance - expectedFee * KEYS_COUNT);
        uint256 moduleId = findModule();
        assertEq(ejector.stakingModuleId(), moduleId);
        IStakingRouter.StakingModule memory moduleInfo = stakingRouter.getStakingModule(moduleId);
        assertEq(moduleInfo.stakingModuleAddress, address(module));
    }
}

contract EjectionTestCSM is EjectionTestBase, CSMIntegrationBase {}

contract EjectionTestCSM0x02 is EjectionTestBase, CSM0x02IntegrationBase {}

contract EjectionTestCurated is EjectionTestBase, CuratedIntegrationBase {}

contract EjectionTest10KeysCSM is EjectionTestBase, CSMIntegrationBase {
    constructor() {
        KEYS_COUNT = 10;
    }
}

contract EjectionTest10KeysCSM0x02 is EjectionTestBase, CSM0x02IntegrationBase {
    constructor() {
        KEYS_COUNT = 10;
    }
}

contract EjectionTest10KeysCurated is EjectionTestBase, CuratedIntegrationBase {
    constructor() {
        KEYS_COUNT = 10;
    }
}
