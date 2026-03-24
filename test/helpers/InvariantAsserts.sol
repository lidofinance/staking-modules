// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IStETH } from "src/interfaces/IStETH.sol";
import { FeeDistributor } from "src/FeeDistributor.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { NodeOperator, IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IStakingModuleV2 } from "src/interfaces/IStakingModule.sol";
import { Batch } from "src/lib/DepositQueueLib.sol";
import { Accounting } from "src/Accounting.sol";
import { ValidatorStrikes } from "src/ValidatorStrikes.sol";
import { FeeOracle } from "src/FeeOracle.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

contract InvariantAsserts is Test {
    bool internal _skipped;
    bool internal _skippedLongForkTest;

    function _profileHash() internal returns (bytes32) {
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        return keccak256(abi.encodePacked(profile));
    }

    function _isCiProfile(bytes32 profileHash) internal pure returns (bool) {
        return profileHash == keccak256(abi.encodePacked("ci"));
    }

    function _isCiQuickProfile(bytes32 profileHash) internal pure returns (bool) {
        return profileHash == keccak256(abi.encodePacked("ci_quick"));
    }

    function skipInvariants() public returns (bool skip) {
        if (_skipped) return true;
        bytes32 profileHash = _profileHash();
        bool isCIProfile = _isCiProfile(profileHash) || _isCiQuickProfile(profileHash);
        bool forkIsActive;
        try vm.activeFork() returns (uint256) {
            forkIsActive = true;
        } catch {}
        skip = !isCIProfile && forkIsActive;
        if (skip) {
            console.log("WARN: Skipping invariants. It only runs with FOUNDRY_PROFILE=ci or ci_quick and active fork");
            _skipped = true;
        }
    }

    function skipLongForkTest() public returns (bool skip) {
        if (_skippedLongForkTest) return true;
        bytes32 profileHash = _profileHash();
        bool isCIProfile = _isCiProfile(profileHash);
        bool forkIsActive;
        try vm.activeFork() returns (uint256) {
            forkIsActive = true;
        } catch {}
        skip = !isCIProfile && forkIsActive;
        if (skip) {
            console.log("WARN: Skipping long fork test. It only runs with FOUNDRY_PROFILE=ci and active fork");
            _skippedLongForkTest = true;
        }
    }

    function assertModuleKeys(IBaseModule csm) public {
        if (skipInvariants()) return;
        if (skipLongForkTest()) return;
        uint256 noCount = csm.getNodeOperatorsCount();
        NodeOperator memory no;

        uint256 totalDepositedValidators;
        uint256 totalExitedValidators;
        uint256 totalDepositableValidators;

        for (uint256 noId = 0; noId < noCount; noId++) {
            no = csm.getNodeOperator(noId);

            assertGe(no.totalAddedKeys, no.totalDepositedKeys, "assert added >= deposited");
            assertGe(no.totalDepositedKeys, no.totalWithdrawnKeys, "assert deposited >= withdrawn");
            assertGe(no.totalVettedKeys, no.totalDepositedKeys, "assert vetted >= deposited");

            assertGe(
                no.totalDepositedKeys - no.totalExitedKeys,
                no.stuckValidatorsCount,
                "assert deposited - exited >= stuck"
            );

            assertGe(
                no.totalAddedKeys,
                no.depositableValidatorsCount + no.totalWithdrawnKeys,
                "assert added >= depositable + withdrawn"
            );
            assertGe(
                no.totalAddedKeys - no.totalDepositedKeys,
                no.depositableValidatorsCount,
                "assert added - deposited >= depositable"
            );

            assertNotEq(no.proposedManagerAddress, no.managerAddress, "assert proposed != manager");
            assertNotEq(no.proposedRewardAddress, no.rewardAddress, "assert proposed != reward");
            assertNotEq(no.managerAddress, address(0), "assert manager != 0");
            assertNotEq(no.rewardAddress, address(0), "assert reward != 0");

            totalExitedValidators += no.totalExitedKeys;
            totalDepositedValidators += no.totalDepositedKeys;
            totalDepositableValidators += no.depositableValidatorsCount;
        }

        (uint256 _totalExitedValidators, uint256 _totalDepositedValidators, uint256 _depositableValidatorsCount) = csm
            .getStakingModuleSummary();
        assertEq(totalExitedValidators, _totalExitedValidators, "assert total exited");
        assertEq(totalDepositedValidators, _totalDepositedValidators, "assert total deposited");
        assertEq(totalDepositableValidators, _depositableValidatorsCount, "assert depositable");

        assertModuleTrackedBalances(csm);
    }

    function assertModuleTrackedBalances(IBaseModule module) public {
        if (skipInvariants()) return;
        if (skipLongForkTest()) return;

        uint256 noCount = module.getNodeOperatorsCount();
        uint256 totalTrackedStake;

        for (uint256 noId = 0; noId < noCount; ++noId) {
            uint256 operatorTrackedStake;
            uint256 totalDepositedKeys = module.getNodeOperator(noId).totalDepositedKeys;
            uint256[] memory keyAllocatedBalances = module.getKeyAllocatedBalances(noId, 0, totalDepositedKeys);

            for (uint256 keyIndex = 0; keyIndex < totalDepositedKeys; ++keyIndex) {
                if (module.isValidatorWithdrawn(noId, keyIndex)) continue;

                operatorTrackedStake += ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + keyAllocatedBalances[keyIndex];
            }

            totalTrackedStake += operatorTrackedStake;

            assertEq(module.getNodeOperatorBalance(noId), operatorTrackedStake, "assert operator tracked balance");
        }

        assertEq(
            IStakingModuleV2(address(module)).getTotalModuleStake(),
            totalTrackedStake,
            "assert total tracked stake"
        );
    }

    mapping(uint256 => uint256) batchKeys;

    function assertModuleEnqueuedCount(ICSModule csm) public {
        if (skipInvariants()) return;
        if (skipLongForkTest()) return;
        uint256 noCount = csm.getNodeOperatorsCount();
        NodeOperator memory no;

        for (uint256 p = 0; p <= csm.PARAMETERS_REGISTRY().QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 head, uint128 tail) = csm.depositQueuePointers(p);

            for (uint128 i = head; i < tail; ) {
                Batch item = csm.depositQueueItem(p, i);
                batchKeys[item.noId()] += item.keys();
                i = item.next();
            }
        }

        for (uint256 noId = 0; noId < noCount; noId++) {
            no = csm.getNodeOperator(noId);
            assertEq(no.enqueuedCount, batchKeys[noId], "assert enqueued == batch keys");
            assertGe(no.enqueuedCount, no.depositableValidatorsCount, "assert enqueued >= depositable");
        }
    }

    function assertModuleUnusedStorageSlots(IBaseModule module) public {
        // @see ModuleLinearStorage.

        if (skipInvariants()) return;

        bytes32 slot1 = vm.load(address(module), bytes32(uint256(1)));

        assertEq(slot1, bytes32(0), "assert __freeSlot1 is empty");
    }

    function assertAccountingTotalBondShares(uint256 nodeOperatorsCount, IStETH steth, Accounting accounting) public {
        if (skipInvariants()) return;
        if (skipLongForkTest()) return;
        uint256 totalNodeOperatorsShares;

        for (uint256 noId = 0; noId < nodeOperatorsCount; noId++) {
            totalNodeOperatorsShares += accounting.getBondShares(noId);
        }
        assertEq(totalNodeOperatorsShares, accounting.totalBondShares(), "total shares mismatch");
        assertGe(steth.sharesOf(address(accounting)), accounting.totalBondShares(), "assert balance >= total shares");
    }

    function assertAccountingBondDebts(uint256 nodeOperatorsCount, Accounting accounting) public {
        if (skipInvariants()) return;
        if (skipLongForkTest()) return;

        for (uint256 noId = 0; noId < nodeOperatorsCount; noId++) {
            uint256 debt = accounting.getBondDebt(noId);
            uint256 bond = accounting.getBond(noId);
            if (debt > 0) assertEq(bond, 0, "assert debt > 0 => bond == 0");
        }
    }

    function assertAccountingBurnerApproval(IStETH steth, address accounting, address burner) public {
        if (skipInvariants()) return;
        assertGe(steth.allowance(accounting, burner), type(uint128).max, "assert allowance");
    }

    function assertAccountingUnusedStorageSlots(Accounting) public {
        if (skipInvariants()) return;
        // NOTE: slot 0 is intentionally reused for `_rewardsClaimers`.
    }

    function assertFeeDistributorClaimableShares(IStETH lido, FeeDistributor feeDistributor) public {
        if (skipInvariants()) return;
        assertGe(
            lido.sharesOf(address(feeDistributor)),
            feeDistributor.totalClaimableShares(),
            "assert balance >= claimable"
        );
    }

    function assertFeeDistributorTree(FeeDistributor feeDistributor) public {
        if (skipInvariants()) return;
        if (feeDistributor.treeRoot() == bytes32(0)) {
            assertEq(feeDistributor.treeCid(), "", "tree doesn't exist, but has CID");
        } else {
            assertNotEq(feeDistributor.treeCid(), "", "tree exists, but has no CID");
        }
    }

    function assertFeeOracleUnusedStorageSlots(FeeOracle feeOracle) public {
        if (skipInvariants()) return;

        bytes32 slot1 = vm.load(address(feeOracle), bytes32(uint256(0)));
        bytes32 slot2 = vm.load(address(feeOracle), bytes32(uint256(1)));

        assertEq(slot1, bytes32(0), "assert __freeSlot1 is empty");
        assertEq(slot2, bytes32(0), "assert __freeSlot2 is empty");
    }

    function assertStrikesTree(ValidatorStrikes strikes) public {
        if (skipInvariants()) return;
        if (strikes.treeRoot() == bytes32(0)) {
            assertEq(strikes.treeCid(), "", "tree doesn't exist, but has CID");
        } else {
            assertNotEq(strikes.treeCid(), "", "tree exists, but has no CID");
        }
    }
}
