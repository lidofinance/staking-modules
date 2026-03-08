// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IExitPenalties, ExitPenaltyInfo } from "src/interfaces/IExitPenalties.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { IValidatorStrikes } from "src/interfaces/IValidatorStrikes.sol";

import { ModuleTypeBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract ParametersRegistryTestBase is ModuleTypeBase {
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal bondCurveId;
    uint256 internal initialKeysCount = 3;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        vm.startPrank(parametersRegistry.getRoleMember(parametersRegistry.DEFAULT_ADMIN_ROLE(), 0));
        parametersRegistry.grantRole(parametersRegistry.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        nodeOperator = nextAddress("NodeOperator");
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
        bondCurveId = accounting.getBondCurveId(defaultNoId);
    }

    function _assertChangeKeyRemovalCharge() internal {
        uint256 newCharge = 0.05 ether;
        parametersRegistry.setKeyRemovalCharge(bondCurveId, newCharge);

        assertEq(
            parametersRegistry.getKeyRemovalCharge(bondCurveId),
            newCharge,
            "Key removal charge should be updated"
        );

        address chargeRecipient = accounting.chargePenaltyRecipient();
        uint256 recipientSharesBefore = lido.sharesOf(chargeRecipient);

        vm.prank(nodeOperator);
        module.removeKeys(defaultNoId, initialKeysCount - 1, 1);

        uint256 recipientSharesAfter = lido.sharesOf(chargeRecipient);
        uint256 chargedShares = recipientSharesAfter - recipientSharesBefore;
        uint256 chargedAmount = lido.getPooledEthByShares(chargedShares);

        assertApproxEqAbs(chargedAmount, newCharge, 2 wei, "Charge recipient should receive key removal charge");
    }

    function _grantStakingRouterRole() internal {
        module.grantRole(module.STAKING_ROUTER_ROLE(), address(this));
    }

    function _getExitPenaltyInfo(bytes memory pubkey) internal view returns (ExitPenaltyInfo memory) {
        return exitPenalties.getExitPenaltyInfo(defaultNoId, pubkey);
    }

    function test_changeGeneralDelayedPenaltyAdditionalFine() public assertInvariants {
        uint256 newFine = 0.1 ether;
        parametersRegistry.setGeneralDelayedPenaltyAdditionalFine(bondCurveId, newFine);

        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(bondCurveId),
            newFine,
            "Additional fine should be updated"
        );

        // Verify fine is applied on penalty report
        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));

        uint256 lockedBefore = accounting.getLockedBond(defaultNoId);
        uint256 penaltyAmount = 0.5 ether;

        module.reportGeneralDelayedPenalty(defaultNoId, bytes32(abi.encode(1)), penaltyAmount, "Test penalty");

        uint256 lockedAfter = accounting.getLockedBond(defaultNoId);

        assertEq(
            lockedAfter - lockedBefore,
            penaltyAmount + newFine,
            "Locked bond should increase by penalty + additional fine"
        );
    }

    function test_setKeysLimit() public assertInvariants {
        uint256 limit = initialKeysCount;
        parametersRegistry.setKeysLimit(bondCurveId, limit);

        assertEq(parametersRegistry.getKeysLimit(bondCurveId), limit, "Keys limit should be updated");

        // NO already has initialKeysCount keys — attempt to add more should revert
        (bytes memory keys, bytes memory signatures) = keysSignatures(1);
        uint256 amount = accounting.getRequiredBondForNextKeys(defaultNoId, 1);
        vm.deal(nodeOperator, amount);

        vm.prank(nodeOperator);
        vm.expectRevert(IBaseModule.KeysLimitExceeded.selector);
        module.addValidatorKeysETH{ value: amount }(nodeOperator, defaultNoId, 1, keys, signatures);
    }

    function test_setMaxElWithdrawalRequestFee() public assertInvariants {
        uint256 newFee = 0.01 ether;
        parametersRegistry.setMaxElWithdrawalRequestFee(bondCurveId, newFee);

        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(bondCurveId),
            newFee,
            "Max EL withdrawal request fee should be updated"
        );

        _grantStakingRouterRole();
        bytes memory pubkey = module.getSigningKeys(defaultNoId, 0, 1);
        module.onValidatorExitTriggered(defaultNoId, pubkey, newFee + 0.01 ether, exitPenalties.STRIKES_EXIT_TYPE_ID());

        ExitPenaltyInfo memory penaltyInfo = _getExitPenaltyInfo(pubkey);
        assertTrue(penaltyInfo.elWithdrawalRequestFee.isValue, "EL withdrawal fee should be recorded");
        assertEq(penaltyInfo.elWithdrawalRequestFee.value, newFee, "EL withdrawal fee should be capped by max value");
    }

    function _assertSetQueueConfig() internal {
        uint256 queueLowestPriority = parametersRegistry.QUEUE_LOWEST_PRIORITY();
        if (queueLowestPriority == 0) {
            vm.skip(true, "No dedicated priority queue on this deployment");
        }

        uint256 priority = queueLowestPriority - 1;
        uint256 maxDeposits = 1;
        parametersRegistry.setQueueConfig(bondCurveId, priority, maxDeposits);

        (uint32 p, uint32 md) = parametersRegistry.getQueueConfig(bondCurveId);
        assertEq(p, priority, "Queue priority should be updated");
        assertEq(md, maxDeposits, "Max deposits should be updated");

        (, uint128 tailPriorityBefore) = module.depositQueuePointers(priority);
        (, uint128 tailLowestBefore) = module.depositQueuePointers(queueLowestPriority);
        integrationHelpers.addNodeOperator(nextAddress("PriorityQueueNO"), 1);
        (, uint128 tailPriorityAfter) = module.depositQueuePointers(priority);
        (, uint128 tailLowestAfter) = module.depositQueuePointers(queueLowestPriority);

        assertGt(tailPriorityAfter, tailPriorityBefore, "Batch should be enqueued to the configured priority queue");
        assertEq(tailLowestAfter, tailLowestBefore, "Batch should not be enqueued to the lowest-priority queue");
    }

    function test_setRewardShareData() public assertInvariants {
        IParametersRegistry.KeyNumberValueInterval[] memory data = new IParametersRegistry.KeyNumberValueInterval[](2);
        data[0] = IParametersRegistry.KeyNumberValueInterval({ minKeyNumber: 1, value: 8000 });
        data[1] = IParametersRegistry.KeyNumberValueInterval({ minKeyNumber: 10, value: 9000 });

        parametersRegistry.setRewardShareData(bondCurveId, data);

        IParametersRegistry.KeyNumberValueInterval[] memory stored = parametersRegistry.getRewardShareData(bondCurveId);
        assertEq(stored.length, 2, "Should have 2 intervals");
        assertEq(stored[0].minKeyNumber, 1, "First minKeyNumber");
        assertEq(stored[0].value, 8000, "First value");
        assertEq(stored[1].minKeyNumber, 10, "Second minKeyNumber");
        assertEq(stored[1].value, 9000, "Second value");
    }

    function test_setPerformanceLeewayData() public assertInvariants {
        IParametersRegistry.KeyNumberValueInterval[] memory data = new IParametersRegistry.KeyNumberValueInterval[](1);
        data[0] = IParametersRegistry.KeyNumberValueInterval({ minKeyNumber: 1, value: 500 });

        parametersRegistry.setPerformanceLeewayData(bondCurveId, data);

        IParametersRegistry.KeyNumberValueInterval[] memory stored = parametersRegistry.getPerformanceLeewayData(
            bondCurveId
        );
        assertEq(stored.length, 1, "Should have 1 interval");
        assertEq(stored[0].value, 500, "Leeway value mismatch");
    }

    function test_setPerformanceCoefficients() public assertInvariants {
        uint256 attW = 7000;
        uint256 blkW = 2000;
        uint256 syncW = 1000;
        parametersRegistry.setPerformanceCoefficients(bondCurveId, attW, blkW, syncW);

        (uint256 a, uint256 b, uint256 s) = parametersRegistry.getPerformanceCoefficients(bondCurveId);
        assertEq(a, attW, "Attestations weight mismatch");
        assertEq(b, blkW, "Blocks weight mismatch");
        assertEq(s, syncW, "Sync weight mismatch");
    }

    function test_setStrikesParams() public assertInvariants {
        uint256 lifetime = 10;
        uint256 threshold = 3;
        parametersRegistry.setStrikesParams(bondCurveId, lifetime, threshold);

        (uint256 lt, uint256 th) = parametersRegistry.getStrikesParams(bondCurveId);
        assertEq(lt, lifetime, "Strikes lifetime mismatch");
        assertEq(th, threshold, "Strikes threshold mismatch");

        uint256[] memory strikesData = new uint256[](1);
        strikesData[0] = threshold - 1;
        bytes memory pubkey = module.getSigningKeys(defaultNoId, 0, 1);
        IValidatorStrikes.KeyStrikes[] memory keyStrikesList = new IValidatorStrikes.KeyStrikes[](1);
        keyStrikesList[0] = IValidatorStrikes.KeyStrikes({
            nodeOperatorId: defaultNoId,
            keyIndex: 0,
            data: strikesData
        });

        bytes32 treeRoot = strikes.hashLeaf(keyStrikesList[0], pubkey);
        vm.prank(address(oracle));
        strikes.processOracleReport(treeRoot, someCIDv0());

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);
        vm.expectRevert(IValidatorStrikes.NotEnoughStrikesToEject.selector);
        strikes.processBadPerformanceProof{ value: 1 wei }(keyStrikesList, proof, proofFlags, address(this));
    }

    function test_setAllowedExitDelay() public assertInvariants {
        uint256 delay = 7200;
        parametersRegistry.setAllowedExitDelay(bondCurveId, delay);

        assertEq(parametersRegistry.getAllowedExitDelay(bondCurveId), delay, "Allowed exit delay should be updated");

        _grantStakingRouterRole();
        bytes memory pubkey = module.getSigningKeys(defaultNoId, 0, 1);

        vm.expectRevert(IExitPenalties.ValidatorExitDelayNotApplicable.selector);
        module.reportValidatorExitDelay(defaultNoId, 12345, pubkey, delay);

        module.reportValidatorExitDelay(defaultNoId, 12345, pubkey, delay + 1);

        ExitPenaltyInfo memory penaltyInfo = _getExitPenaltyInfo(pubkey);
        assertTrue(penaltyInfo.delayFee.isValue, "Delay fee should be recorded");
        assertEq(
            penaltyInfo.delayFee.value,
            parametersRegistry.getExitDelayFee(bondCurveId),
            "Delay fee should match current curve setting"
        );
    }

    function test_setExitDelayFee() public assertInvariants {
        uint256 fee = 0.02 ether;
        parametersRegistry.setExitDelayFee(bondCurveId, fee);

        assertEq(parametersRegistry.getExitDelayFee(bondCurveId), fee, "Exit delay fee should be updated");

        parametersRegistry.setAllowedExitDelay(bondCurveId, 1);
        _grantStakingRouterRole();
        bytes memory pubkey = module.getSigningKeys(defaultNoId, 0, 1);

        module.reportValidatorExitDelay(defaultNoId, 12345, pubkey, 2);

        ExitPenaltyInfo memory penaltyInfo = _getExitPenaltyInfo(pubkey);
        assertTrue(penaltyInfo.delayFee.isValue, "Delay fee should be recorded");
        assertEq(penaltyInfo.delayFee.value, fee, "Delay fee should match updated value");
    }

    function test_setBadPerformancePenalty() public assertInvariants {
        uint256 penalty = 0.05 ether;
        parametersRegistry.setBadPerformancePenalty(bondCurveId, penalty);

        assertEq(
            parametersRegistry.getBadPerformancePenalty(bondCurveId),
            penalty,
            "Bad performance penalty should be updated"
        );

        bytes memory pubkey = module.getSigningKeys(defaultNoId, 0, 1);
        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(defaultNoId, pubkey);

        ExitPenaltyInfo memory penaltyInfo = _getExitPenaltyInfo(pubkey);
        assertTrue(penaltyInfo.strikesPenalty.isValue, "Strikes penalty should be recorded");
        assertEq(penaltyInfo.strikesPenalty.value, penalty, "Strikes penalty should match updated value");
    }
}

contract ParametersRegistryTestCurated is ParametersRegistryTestBase, CuratedIntegrationBase {}
