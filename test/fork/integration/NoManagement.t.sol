// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { NodeOperatorManagementProperties } from "../../../src/interfaces/ICSModule.sol";

contract NoManagementBaseTest is Test, Utilities, DeploymentFixtures {
    address public nodeOperator;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        nodeOperator = nextAddress("nodeOperator");
    }

    function _createNodeOperator(
        address manager,
        address reward,
        bool extendedPermissions
    ) internal returns (uint256 noId) {
        uint256 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 amount = accounting.getBondAmountByKeysCount(
            keysCount,
            permissionlessGate.CURVE_ID()
        );
        vm.deal(nodeOperator, amount);

        vm.startPrank(nodeOperator);
        noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extendedPermissions
            }),
            referrer: address(0)
        });
        vm.stopPrank();
    }
}

contract NoAddressesBasicPermissionsTest is NoManagementBaseTest {
    bool internal immutable extended;

    constructor() {
        extended = false;
    }

    function test_changeManagerAddresses() public {
        address newManager = nextAddress("newManager");

        uint256 noId = _createNodeOperator(
            nodeOperator,
            nodeOperator,
            extended
        );
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.proposeNodeOperatorManagerAddressChange");
        module.proposeNodeOperatorManagerAddressChange(noId, newManager);
        vm.stopSnapshotGas();

        vm.prank(newManager);
        vm.startSnapshotGas("module.confirmNodeOperatorManagerAddressChange");
        module.confirmNodeOperatorManagerAddressChange(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).managerAddress,
            newManager
        );
    }

    function test_changeRewardAddresses() public {
        address newReward = nextAddress("newReward");

        uint256 noId = _createNodeOperator(
            nodeOperator,
            nodeOperator,
            extended
        );
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.proposeNodeOperatorRewardAddressChange");
        module.proposeNodeOperatorRewardAddressChange(noId, newReward);
        vm.stopSnapshotGas();

        vm.prank(newReward);
        vm.startSnapshotGas("module.confirmNodeOperatorRewardAddressChange");
        module.confirmNodeOperatorRewardAddressChange(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).rewardAddress,
            newReward
        );
    }
}

contract NoAddressesExtendedPermissionsTest is NoAddressesBasicPermissionsTest {
    constructor() {
        extended = true;
    }
}

contract NoAddressesPermissionsTest is NoManagementBaseTest {
    function test_resetManagerAddresses() public {
        address someManager = nextAddress("someManager");

        uint256 noId = _createNodeOperator(someManager, nodeOperator, false);

        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.resetNodeOperatorManagerAddress");
        module.resetNodeOperatorManagerAddress(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).managerAddress,
            nodeOperator
        );
    }

    function test_changeRewardAddresses() public {
        address newReward = nextAddress("newReward");

        uint256 noId = _createNodeOperator(nodeOperator, nodeOperator, true);
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.changeNodeOperatorRewardAddress");
        module.changeNodeOperatorRewardAddress(noId, newReward);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).rewardAddress,
            newReward
        );
    }
}
