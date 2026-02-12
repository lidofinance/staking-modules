// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

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
        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
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

        module.settleGeneralDelayedPenalty(idsToSettle, UintArr(type(uint256).max));

        (uint256 bondAfter, ) = accounting.getBondSummaryShares(defaultNoId);

        assertEq(bondAfter, bondBefore - amountShares);
    }
}

contract PenaltyIntegrationTestCSM is PenaltyIntegrationTestBase, CSMIntegrationBase {}

contract PenaltyIntegrationTestCSM0x02 is PenaltyIntegrationTestBase, CSM0x02IntegrationBase {}

contract PenaltyIntegrationTestCurated is PenaltyIntegrationTestBase, CuratedIntegrationBase {}
