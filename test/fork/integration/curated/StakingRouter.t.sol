// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStakingModuleV2 } from "src/interfaces/IStakingModule.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { MetaRegistry } from "src/MetaRegistry.sol";

import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";
import { StakingRouterIntegrationTestBase } from "../common/StakingRouter.t.sol";

contract StakingRouterIntegrationTestCurated is StakingRouterIntegrationTestBase, CuratedIntegrationBase {
    uint256 internal constant TOP_UP_ALLOCATION_PROBE_AMOUNT = 10_000_000 ether;

    address internal topUpGateway;

    function setUp() public override {
        super.setUp();
        if (!isStakingRouterUpgraded) {
            // Skip: this suite depends on router/core v2 APIs and is not executable on the old router version.
            vm.skip(true, "Suite requires upgraded staking router version for router/core v2 APIs");
        }

        topUpGateway = locator.topUpGateway();

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
        integrationHelpers.getDepositableNodeOperator(nextAddress());

        _setAllCuratedCurveWeightsToZero();

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

        (uint256 expectedMaxDepositAmount, ) = stakingRouter.getTopUpAllocation(TOP_UP_ALLOCATION_PROBE_AMOUNT);
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

    function _setAllCuratedCurveWeightsToZero() internal {
        MetaRegistry registry = MetaRegistry(address(ICuratedModule(address(module)).META_REGISTRY()));

        address admin = registry.getRoleMember(registry.DEFAULT_ADMIN_ROLE(), 0);
        bytes32 role = registry.SET_BOND_CURVE_WEIGHT_ROLE();
        if (!registry.hasRole(role, address(this))) {
            vm.prank(admin);
            registry.grantRole(role, address(this));
        }

        uint256 operatorsCount = module.getNodeOperatorsCount();
        for (uint256 i; i < operatorsCount; ++i) {
            uint256 curveId = accounting.getBondCurveId(i);
            if (registry.getBondCurveWeight(curveId) != 0) {
                registry.setBondCurveWeight(curveId, 0);
            }
            registry.refreshOperatorWeight(i);
        }
    }
}
