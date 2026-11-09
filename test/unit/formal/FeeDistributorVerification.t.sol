// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { FeeDistributor } from "src/FeeDistributor.sol";
import { IFeeDistributor } from "src/interfaces/IFeeDistributor.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { FeeDistributorHarness } from "certora/harnesses/FeeDistributorHarness.sol";
import { FeeTokenModel } from "certora/models/FeeTokenModel.sol";

/// @notice Executable cross-checks for the FeeDistributor verification boundary.
/// @dev These use the real implementation through a proxy, real Merkle verification,
///      and the exact-share model. They are fuzz tests, not formal proof results.
contract FeeDistributorVerificationTest is Test {
    address private constant ACCOUNTING = address(0xA11CE);
    address private constant ORACLE = address(0xB0B);
    address private constant REBATE_RECIPIENT = address(0xCAFE);

    FeeTokenModel private token;
    FeeDistributorHarness private distributor;

    function setUp() public {
        token = new FeeTokenModel();
        FeeDistributorHarness implementation = new FeeDistributorHarness(address(token), ACCOUNTING, ORACLE);
        distributor = FeeDistributorHarness(
            address(
                new OssifiableProxy(
                    address(implementation),
                    address(this),
                    abi.encodeCall(FeeDistributor.initialize, (address(this), REBATE_RECIPIENT))
                )
            )
        );
    }

    function testFuzz_cumulativeClaimsConserveShares(
        uint256 id,
        uint128 first,
        uint128 increase,
        bytes32 sibling
    ) public {
        vm.assume(first > 0 && increase > 0);
        uint256 cumulative = uint256(first) + increase;
        bytes32[] memory proof = _proof(sibling);

        token.mintShares(address(distributor), first);
        _report(distributor.rootForOneSibling(id, first, sibling), "tree-1", "log-1", first, 0);
        vm.prank(ACCOUNTING);
        assertEq(distributor.distributeFees(id, first, proof), first);

        token.mintShares(address(distributor), increase);
        _report(distributor.rootForOneSibling(id, cumulative, sibling), "tree-2", "log-2", increase, 0);
        vm.prank(ACCOUNTING);
        assertEq(distributor.distributeFees(id, cumulative, proof), increase);

        assertEq(distributor.distributedShares(id), cumulative);
        assertEq(distributor.distributedShares(id ^ 1), 0);
        assertEq(token.sharesOf(ACCOUNTING), cumulative);
        assertEq(token.sharesOf(address(distributor)), 0);
        assertEq(distributor.totalClaimableShares(), 0);

        vm.prank(ACCOUNTING);
        assertEq(distributor.distributeFees(id, cumulative, proof), 0);
        assertEq(token.sharesOf(ACCOUNTING), cumulative);
    }

    function test_singleClaimUpdatesEntitlementAndObligation() public {
        uint256 id = 42;
        uint256 amount = 11;
        bytes32 sibling = bytes32(uint256(1));
        token.mintShares(address(distributor), amount);
        _report(distributor.rootForOneSibling(id, amount, sibling), "tree", "log", amount, 0);

        vm.prank(ACCOUNTING);
        uint256 paid = distributor.distributeFees(id, amount, _proof(sibling));

        assertEq(paid, amount);
        assertEq(distributor.distributedShares(id), amount);
        assertEq(distributor.totalClaimableShares(), 0);
        assertEq(token.sharesOf(address(distributor)), 0);
        assertEq(token.sharesOf(ACCOUNTING), amount);
    }

    function testFuzz_reportPreservesFundingAndHistory(uint128 distributed, uint128 rebate, uint128 surplus) public {
        vm.assume(distributed > 0);
        uint256 funded = uint256(distributed) + rebate + surplus;
        token.mintShares(address(distributor), funded);
        _report(bytes32(uint256(1)), "tree", "log", distributed, rebate);

        assertEq(distributor.totalClaimableShares(), distributed);
        assertEq(token.sharesOf(address(distributor)), uint256(distributed) + surplus);
        assertEq(token.sharesOf(REBATE_RECIPIENT), rebate);
        assertEq(distributor.pendingSharesToDistribute(), surplus);
        assertEq(distributor.distributionDataHistoryCount(), 1);
        assertEq(distributor.historyDistributed(0), distributed);
        assertEq(distributor.historyRebate(0), rebate);
        assertEq(distributor.historyRefSlot(0), 123);
        assertEq(distributor.historyTreeRoot(0), bytes32(uint256(1)));
    }

    function testFuzz_rebateRecipientSelfAliasPreservesFunding(uint128 distributed, uint128 rebate) public {
        vm.assume(distributed > 0 && rebate > 0);
        distributor.setRebateRecipient(address(distributor));
        uint256 funded = uint256(distributed) + rebate;
        token.mintShares(address(distributor), funded);
        _report(bytes32(uint256(1)), "tree", "log", distributed, rebate);

        assertEq(token.sharesOf(address(distributor)), funded);
        assertEq(distributor.totalClaimableShares(), distributed);
        assertGe(token.sharesOf(address(distributor)), distributor.totalClaimableShares());
    }

    function testFuzz_accountingSelfAliasPreservesShares(uint128 amount, bytes32 sibling) public {
        vm.assume(amount > 0);
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        FeeDistributorHarness selfAccounting = new FeeDistributorHarness(address(token), predicted, ORACLE);
        assertEq(address(selfAccounting), predicted);

        token.mintShares(address(selfAccounting), amount);
        bytes32 root = selfAccounting.rootForOneSibling(1, amount, sibling);
        vm.prank(ORACLE);
        selfAccounting.processOracleReport(root, "tree", "log", amount, 0, 123);

        vm.prank(address(selfAccounting));
        assertEq(selfAccounting.distributeFees(1, amount, _proof(sibling)), amount);
        assertEq(token.sharesOf(address(selfAccounting)), amount);
        assertEq(selfAccounting.totalClaimableShares(), 0);
    }

    function test_validProofCannotDecreaseCumulativeEntitlement() public {
        uint256 id = 42;
        bytes32 sibling = bytes32(uint256(1));
        bytes32[] memory proof = _proof(sibling);
        token.mintShares(address(distributor), 100);
        _report(distributor.rootForOneSibling(id, 100, sibling), "tree-1", "log-1", 100, 0);
        vm.prank(ACCOUNTING);
        distributor.distributeFees(id, 100, proof);

        token.mintShares(address(distributor), 1);
        _report(distributor.rootForOneSibling(id, 99, sibling), "tree-2", "log-2", 1, 0);
        vm.prank(ACCOUNTING);
        vm.expectRevert(IFeeDistributor.FeeSharesDecrease.selector);
        distributor.distributeFees(id, 99, proof);
    }

    function test_proofBindsOperatorAndCumulativeAmount() public {
        bytes32 sibling = bytes32(uint256(1));
        token.mintShares(address(distributor), 100);
        _report(distributor.rootForOneSibling(42, 100, sibling), "tree", "log", 100, 0);

        vm.startPrank(ACCOUNTING);
        vm.expectRevert(IFeeDistributor.InvalidProof.selector);
        distributor.distributeFees(43, 100, _proof(sibling));
        vm.expectRevert(IFeeDistributor.InvalidProof.selector);
        distributor.distributeFees(42, 101, _proof(sibling));
        vm.stopPrank();
    }

    function test_unfundedReportReverts() public {
        token.mintShares(address(distributor), 99);
        vm.prank(ORACLE);
        vm.expectRevert(IFeeDistributor.InvalidShares.selector);
        distributor.processOracleReport(bytes32(uint256(1)), "tree", "log", 100, 0, 123);
    }

    function test_validProofCannotExceedGlobalDistributionBudget() public {
        bytes32 sibling = bytes32(uint256(1));
        token.mintShares(address(distributor), 100);
        _report(distributor.rootForOneSibling(42, 101, sibling), "tree", "log", 100, 0);

        vm.prank(ACCOUNTING);
        vm.expectRevert(IFeeDistributor.NotEnoughShares.selector);
        distributor.distributeFees(42, 101, _proof(sibling));
    }

    function test_emptyProofIsRejectedEvenWhenLeafEqualsRoot() public {
        token.mintShares(address(distributor), 100);
        _report(distributor.hashLeaf(42, 100), "tree", "log", 100, 0);

        vm.prank(ACCOUNTING);
        vm.expectRevert(IFeeDistributor.InvalidProof.selector);
        distributor.distributeFees(42, 100, new bytes32[](0));
    }

    function test_reportReplacesLongStoredCids() public {
        bytes memory treeCid = new bytes(64);
        bytes memory logCid = new bytes(59);
        treeCid[63] = bytes1(uint8(1));
        logCid[58] = bytes1(uint8(1));
        token.mintShares(address(distributor), 2);
        _report(bytes32(uint256(1)), string(treeCid), string(logCid), 1, 0);
        assertEq(distributor.treeCidLength(), 64);
        assertEq(distributor.logCidLength(), 59);

        _report(bytes32(uint256(2)), "short-tree", "short-log", 1, 0);
        assertEq(distributor.treeCid(), "short-tree");
        assertEq(distributor.logCid(), "short-log");
        assertEq(distributor.totalClaimableShares(), 2);
    }

    function test_recoveryGuardAppliesToAuthorizedRecoverer() public {
        bytes32 role = distributor.RECOVERER_ROLE();
        distributor.grantRole(role, address(this));
        token.mintShares(address(distributor), 100);
        vm.expectRevert(IAssetRecovererLib.NotAllowedToRecover.selector);
        distributor.recoverERC20(address(token), 100);
    }

    function test_reportAndDistributionRequireAuthorizedCallers() public {
        vm.expectRevert(IFeeDistributor.SenderIsNotOracle.selector);
        distributor.processOracleReport(bytes32(uint256(1)), "tree", "log", 1, 0, 123);

        vm.expectRevert(IFeeDistributor.SenderIsNotAccounting.selector);
        distributor.distributeFees(1, 1, _proof(bytes32(uint256(1))));
    }

    function _report(
        bytes32 root,
        string memory treeCid,
        string memory logCid,
        uint256 distributed,
        uint256 rebate
    ) private {
        vm.prank(ORACLE);
        distributor.processOracleReport(root, treeCid, logCid, distributed, rebate, 123);
    }

    function _proof(bytes32 sibling) private pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = sibling;
    }
}
