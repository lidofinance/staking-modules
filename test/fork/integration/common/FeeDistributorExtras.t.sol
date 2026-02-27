// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IFeeDistributor } from "src/interfaces/IFeeDistributor.sol";

import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract FeeDistributorExtrasTestBase is ModuleTypeBase {
    address internal user;
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
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        user = nextAddress("User");
        nodeOperator = nextAddress("NodeOperator");

        uint256 keysCount = 5;
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, keysCount);
    }

    /// @dev Funds feeDistributor with stETH shares and returns the amount of shares deposited
    function _fundFeeDistributor(uint256 ethAmount) internal returns (uint256 shares) {
        vm.startPrank(user);
        vm.deal(user, ethAmount);
        shares = lido.submit{ value: ethAmount }(address(0));
        lido.transferShares(address(feeDistributor), shares);
        vm.stopPrank();
    }

    function test_rebateMechanism() public assertInvariants {
        uint256 totalFunding = 2 ether;
        uint256 shares = _fundFeeDistributor(totalFunding);

        // Split shares between distributed and rebate
        uint256 distributed = (shares * 80) / 100;
        uint256 rebate = shares - distributed;

        address rebateAddr = feeDistributor.rebateRecipient();
        uint256 rebateSharesBefore = lido.sharesOf(rebateAddr);

        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, distributed));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.RebateTransferred(rebate);

        vm.startPrank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(tree.root(), someCIDv0(), someCIDv0(), distributed, rebate, 154);
        vm.stopPrank();

        uint256 rebateSharesAfter = lido.sharesOf(rebateAddr);
        assertEq(rebateSharesAfter - rebateSharesBefore, rebate, "Rebate recipient should receive rebate shares");
    }
}

contract FeeDistributorExtrasTestCSM is FeeDistributorExtrasTestBase, CSMIntegrationBase {}

contract FeeDistributorExtrasTestCSM0x02 is FeeDistributorExtrasTestBase, CSM0x02IntegrationBase {}

contract FeeDistributorExtrasTestCurated is FeeDistributorExtrasTestBase, CuratedIntegrationBase {}
