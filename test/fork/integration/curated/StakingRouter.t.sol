// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStakingModuleV2 } from "src/interfaces/IStakingModule.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { MetaRegistry } from "src/MetaRegistry.sol";

import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";
import { StakingRouterIntegrationTestBase } from "../common/StakingRouter.t.sol";

contract StakingRouterIntegrationTestCurated is StakingRouterIntegrationTestBase, CuratedIntegrationBase {
    address internal topUpGateway;

    function setUp() public override {
        super.setUp();
        if (!isStakingRouterUpgraded) {
            // Skip: this suite depends on router/core v2 APIs and is not executable on the old router version.
            vm.skip(true, "Suite requires upgraded staking router version for router/core v2 APIs");
        }

        topUpGateway = locator.topUpGateway();

        address metaRegistryAdmin = metaRegistry.getRoleMember(metaRegistry.DEFAULT_ADMIN_ROLE(), 0);
        bytes32 manageOperatorGroupsRole = metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE();
        vm.prank(metaRegistryAdmin);
        metaRegistry.grantRole(manageOperatorGroupsRole, address(this));

        _maximizeModuleShare(moduleId);
        _disableDepositsForOtherModules(moduleId);
        hugeDeposit();
        _ensureStakingRouterCanDeposit(moduleId);
    }

    function test_routerDeposit_happyPath_callsObtainDepositDataAndUsesReturnedCount() public assertInvariants {
        integrationHelpers.getDepositableNodeOperator(nextAddress());

        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();

        uint256 requestedDeposits = _getExpectedRouterDepositRequestCount();
        assertGt(requestedDeposits, 0);
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(module.obtainDepositData.selector, requestedDeposits, "")
        );
        vm.prank(locator.depositSecurityModule());
        stakingRouter.deposit(moduleId, "");

        (, uint256 depositedAfter, ) = module.getStakingModuleSummary();
        uint256 actualDeposits = depositedAfter - depositedBefore;
        assertEq(depositedAfter - depositedBefore, actualDeposits);
        assertGt(actualDeposits, 0);
        assertLe(actualDeposits, requestedDeposits);
    }

    function test_routerDeposit_curatedCanReturnLessThanRequested() public assertInvariants {
        _clearAllOperatorGroups(metaRegistry);

        address overweightOperatorOwner = nextAddress();
        uint256 overweightOperatorId = integrationHelpers.addNodeOperator(overweightOperatorOwner, 10);

        vm.startPrank(address(stakingRouter));
        module.obtainDepositData(10, "");
        vm.stopPrank();

        _addValidatorKeys(overweightOperatorOwner, overweightOperatorId, 10, 10);

        integrationHelpers.addNodeOperator(nextAddress(), 1);

        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();

        uint256 requestedDeposits = _getExpectedRouterDepositRequestCount();
        assertGt(requestedDeposits, 1);
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(module.obtainDepositData.selector, requestedDeposits, "")
        );
        vm.prank(locator.depositSecurityModule());
        stakingRouter.deposit(moduleId, "");

        (, uint256 depositedAfter, ) = module.getStakingModuleSummary();
        uint256 actualDeposits = depositedAfter - depositedBefore;
        assertEq(depositedAfter - depositedBefore, actualDeposits);
        assertEq(actualDeposits, 2);
        assertLt(actualDeposits, requestedDeposits);
    }

    function test_routerTopUp_callsAllocateDeposits() public assertInvariants {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, 1 ether);

        uint256 expectedMaxDepositAmount = _getExpectedRouterTopUpAmount();
        uint256 keyAllocatedBalanceBefore = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        ICuratedModule curatedModule = ICuratedModule(address(module));
        uint256 operatorBalanceBefore = curatedModule.getNodeOperatorBalance(noId);

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                IStakingModuleV2.allocateDeposits.selector,
                expectedMaxDepositAmount,
                pubkeys,
                keyIndices,
                operatorIds,
                topUpLimits
            )
        );

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        uint256 keyAllocatedBalanceAfter = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        uint256 operatorBalanceAfter = curatedModule.getNodeOperatorBalance(noId);
        uint256 keyDelta = keyAllocatedBalanceAfter - keyAllocatedBalanceBefore;
        uint256 operatorDelta = operatorBalanceAfter - operatorBalanceBefore;

        assertEq(operatorDelta, keyDelta);
        assertLe(keyDelta, topUpLimits[0]);
        assertLe(keyDelta, expectedMaxDepositAmount);
        assertEq(keyDelta % 1 ether, 0);
    }

    function test_routerTopUp_subEtherLimitDoesNotAllocate() public assertInvariants {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, 0.5 ether);

        ICuratedModule curatedModule = ICuratedModule(address(module));
        uint256 keyAllocatedBalanceBefore = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        uint256 operatorBalanceBefore = curatedModule.getNodeOperatorBalance(noId);

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        assertEq(module.getKeyAllocatedBalances(noId, keyIndex, 1)[0], keyAllocatedBalanceBefore);
        assertEq(curatedModule.getNodeOperatorBalance(noId), operatorBalanceBefore);
    }

    function test_routerTopUp_revertsOnInvalidSigningKey() public {
        (uint256 noId, uint256 keyIndex, ) = integrationHelpers.getDepositableTopUpNodeOperator(nextAddress());
        bytes memory invalidPubkey = new bytes(48);
        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, invalidPubkey, 1 ether);

        vm.expectRevert(SigningKeys.InvalidSigningKey.selector);
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);
    }

    function _singleTopUpArrays(
        uint256 noId,
        uint256 keyIndex,
        bytes memory pubkey,
        uint256 topUpLimit
    )
        internal
        pure
        returns (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        )
    {
        keyIndices = new uint256[](1);
        keyIndices[0] = keyIndex;

        operatorIds = new uint256[](1);
        operatorIds[0] = noId;

        pubkeys = new bytes[](1);
        pubkeys[0] = pubkey;

        topUpLimits = new uint256[](1);
        topUpLimits[0] = topUpLimit;
    }

    function _addValidatorKeys(address owner, uint256 nodeOperatorId, uint256 keysCount, uint256 startIndex) internal {
        (bytes memory keys, bytes memory signatures) = keysSignatures(keysCount, startIndex);
        uint256 amount = accounting.getRequiredBondForNextKeys(nodeOperatorId, keysCount);

        vm.deal(owner, amount);
        vm.prank(owner);
        module.addValidatorKeysETH{ value: amount }(owner, nodeOperatorId, keysCount, keys, signatures);
    }

    function _clearAllOperatorGroups(MetaRegistry registry) internal {
        IMetaRegistry.OperatorGroup memory emptyGroup;
        uint256 groupsCount = registry.getOperatorGroupsCount();
        for (uint256 groupId = 1; groupId < groupsCount; ++groupId) {
            registry.createOrUpdateOperatorGroup(groupId, emptyGroup);
        }
    }
}
