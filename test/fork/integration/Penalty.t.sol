// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { PermitHelper } from "../../helpers/Permit.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";

contract PenaltyIntegrationTest is
    Test,
    Utilities,
    PermitHelper,
    DeploymentFixtures,
    InvariantAsserts
{
    address internal user;
    address internal stranger;
    address internal nodeOperator;
    uint256 internal defaultNoId;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        assertModuleEnqueuedCount(module);
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(
            lido,
            address(accounting),
            locator.burner()
        );
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        module.grantRole(
            module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        module.grantRole(
            module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        user = nextAddress("User");
        stranger = nextAddress("stranger");
        nodeOperator = nextAddress("NodeOperator");

        uint256 keysCount = 5;
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 amount = accounting.getBondAmountByKeysCount(keysCount, 0);
        vm.deal(nodeOperator, amount);

        vm.prank(nodeOperator);
        defaultNoId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
    }

    function test_generalDelayedPenalty() public assertInvariants {
        uint256 amount = 1 ether;

        uint256 amountShares = lido.getSharesByPooledEth(amount);

        (uint256 bondBefore, ) = accounting.getBondSummaryShares(defaultNoId);

        module.reportGeneralDelayedPenalty(
            defaultNoId,
            bytes32(abi.encode(1)),
            amount -
                module
                    .PARAMETERS_REGISTRY()
                    .getGeneralDelayedPenaltyAdditionalFine(
                        accounting.getBondCurveId(defaultNoId)
                    ),
            "Test penalty"
        );

        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = defaultNoId;

        module.settleGeneralDelayedPenalty(
            idsToSettle,
            UintArr(type(uint256).max)
        );

        (uint256 bondAfter, ) = accounting.getBondSummaryShares(defaultNoId);

        assertEq(bondAfter, bondBefore - amountShares);
    }
}
