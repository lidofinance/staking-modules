// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";

import { DeploymentFixtures } from "test/helpers/Fixtures.sol";

import { ForkHelpersCommon } from "./Common.sol";

contract MetaRegistryHelpers is Script, DeploymentFixtures, ForkHelpersCommon {
    modifier broadcastGroupManager() {
        _setUp();
        address manager = metaRegistry.getRoleMember(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE(), 0);
        _setBalance(manager);
        vm.startBroadcast(manager);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastWeightSetter() {
        _setUp();
        address setter = metaRegistry.getRoleMember(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE(), 0);
        _setBalance(setter);
        vm.startBroadcast(setter);
        _;
        vm.stopBroadcast();
    }

    /// @notice Create operator group from flat pairs [noId1, share1, noId2, share2, ...].
    ///         Shares are in basis points and must sum to 10000.
    function createOperatorGroup(uint256[] calldata pairs) external broadcastGroupManager {
        require(pairs.length >= 2 && pairs.length % 2 == 0, "pairs: even length >= 2");

        uint256 count = pairs.length / 2;
        IMetaRegistry.SubNodeOperator[] memory subs = new IMetaRegistry.SubNodeOperator[](count);
        for (uint256 i; i < count; ++i) {
            subs[i] = IMetaRegistry.SubNodeOperator({
                nodeOperatorId: uint64(pairs[i * 2]),
                share: uint16(pairs[i * 2 + 1])
            });
        }

        IMetaRegistry.OperatorGroup memory group;
        group.subNodeOperators = subs;

        metaRegistry.createOrUpdateOperatorGroup(metaRegistry.NO_GROUP_ID(), group);
    }

    /// @notice Reset the operator group that contains the given node operator.
    function resetOperatorGroup(uint256 noId) external broadcastGroupManager {
        uint256 groupId = metaRegistry.getNodeOperatorGroupId(noId);
        require(groupId != metaRegistry.NO_GROUP_ID(), "operator not in a group");

        IMetaRegistry.OperatorGroup memory empty;
        metaRegistry.createOrUpdateOperatorGroup(groupId, empty);
    }

    /// @notice Set bond curve weight.
    function setBondCurveWeight(uint256 curveId, uint256 weight) external broadcastWeightSetter {
        metaRegistry.setBondCurveWeight(curveId, weight);
    }
}
