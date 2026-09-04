// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { PermitHelper } from "../../../helpers/Permit.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract PenaltyIntegrationTestBase is ModuleTypeBase, PermitHelper {
    address internal user;
    address internal stranger;
    address internal nodeOperator;
    uint256 internal defaultNoId;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
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
        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.VERIFIER_ROLE(), address(this));
        module.grantRole(module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        user = nextAddress("User");
        stranger = nextAddress("stranger");
        nodeOperator = nextAddress("NodeOperator");

        uint256 keysCount = 5;
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, keysCount);
    }

    function test_generalDelayedPenalty() public assertInvariants {
        uint256 amount = 1 ether;

        uint256 amountShares = lido.getSharesByPooledEth(amount);

        (uint256 bondBefore, ) = accounting.getBondSummaryShares(defaultNoId);

        module.reportGeneralDelayedPenalty(
            defaultNoId,
            bytes32(abi.encode(1)),
            amount -
                module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(
                    accounting.getBondCurveId(defaultNoId)
                ),
            "Test penalty"
        );

        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = defaultNoId;

        uint256 bondLockNonce = accounting.getBondLockNonce(defaultNoId);

        module.settleGeneralDelayedPenalty(idsToSettle, UintArr(bondLockNonce));

        (uint256 bondAfter, ) = accounting.getBondSummaryShares(defaultNoId);

        assertEq(bondAfter, bondBefore - amountShares);
    }

    function test_bondClaimRestrictionAfterSlashing() public assertInvariants {
        uint256 noId = integrationHelpers.getDepositedNodeOperator(nextAddress(), 1);
        uint256 keyIndex = _activeNonSlashedKeyIndex(noId);
        address rewardAddress = module.getNodeOperator(noId).rewardAddress;

        uint256 excessBond = 1 ether;
        uint256 topUp = accounting.getRequiredBondForNextKeys(noId, 0) + excessBond;
        vm.deal(user, topUp);
        vm.prank(user);
        accounting.depositETH{ value: topUp }(noId);
        assertGt(accounting.getClaimableBondShares(noId), 0);

        module.reportValidatorSlashing(noId, keyIndex);

        assertTrue(accounting.isBondClaimRestricted(noId));
        assertEq(accounting.getClaimableBondShares(noId), 0);

        uint256 rewardSharesBefore = lido.sharesOf(rewardAddress);
        vm.prank(rewardAddress);
        uint256 claimedShares = accounting.claimRewardsStETH(noId, type(uint256).max, 0, new bytes32[](0));
        assertEq(claimedShares, 0);
        assertEq(lido.sharesOf(rewardAddress), rewardSharesBefore);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: excessBond / 10,
            isSlashed: true
        });
        module.reportSlashedWithdrawnValidators(validatorInfos);

        assertFalse(accounting.isBondClaimRestricted(noId));
        assertGt(accounting.getClaimableBondShares(noId), 0);
    }

    function _activeNonSlashedKeyIndex(uint256 noId) internal view returns (uint256) {
        uint256 totalDepositedKeys = module.getNodeOperator(noId).totalDepositedKeys;
        for (uint256 keyIndex; keyIndex < totalDepositedKeys; ++keyIndex) {
            if (module.isValidatorWithdrawn(noId, keyIndex)) continue;
            if (module.isValidatorSlashed(noId, keyIndex)) continue;
            return keyIndex;
        }
        revert("no active non-slashed key");
    }
}

contract PenaltyIntegrationTestCSM is PenaltyIntegrationTestBase, CSMIntegrationBase {}

contract PenaltyIntegrationTestCSM0x02 is PenaltyIntegrationTestBase, CSM0x02IntegrationBase {}

contract PenaltyIntegrationTestCurated is PenaltyIntegrationTestBase, CuratedIntegrationBase {}
