// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script, console } from "forge-std/Script.sol";

import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IVEBO } from "src/interfaces/IVEBO.sol";
import { IStakingRouter } from "src/interfaces/IStakingRouter.sol";
import { NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";

import { DeploymentFixtures } from "test/helpers/Fixtures.sol";
import { Utilities } from "test/helpers/Utilities.sol";
import { MerkleTree } from "test/helpers/MerkleTree.sol";
import { CuratedGate } from "src/CuratedGate.sol";

import { ForkHelpersCommon } from "./Common.sol";

contract NodeOperators is Script, DeploymentFixtures, ForkHelpersCommon, Utilities {
    modifier broadcastPenaltyReporter() {
        _setUp();
        address penaltyReporter = module.getRoleMember(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), 0);
        _setBalance(penaltyReporter);
        vm.startBroadcast(penaltyReporter);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastPenaltySettler() {
        _setUp();
        address penaltySettler = module.getRoleMember(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), 0);
        _setBalance(penaltySettler);
        vm.startBroadcast(penaltySettler);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastVerifier() {
        _setUp();
        _setBalance(address(verifier));
        vm.startBroadcast(address(verifier));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastModule() {
        _setUp();
        _setBalance(address(module));
        vm.startBroadcast(address(module));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastStakingRouter() {
        _setUp();
        _setBalance(address(stakingRouter));
        vm.startBroadcast(address(stakingRouter));
        _;
        vm.stopBroadcast();
    }

    modifier broadcastStranger() {
        _setUp();
        address stranger = nextAddress("stranger");
        _setBalance(stranger);
        vm.startBroadcast(stranger);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastManager(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).managerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastProposedManager(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).proposedManagerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastReward(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).managerAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastProposedReward(uint256 noId) {
        _setUp();
        address nodeOperator = module.getNodeOperator(noId).proposedRewardAddress;
        _setBalance(nodeOperator);
        vm.startBroadcast(nodeOperator);
        _;
        vm.stopBroadcast();
    }

    function proposeManagerAddress(uint256 noId, address managerAddress) external broadcastManager(noId) {
        module.proposeNodeOperatorManagerAddressChange(noId, managerAddress);
    }

    function proposeRewardAddress(uint256 noId, address rewardAddress) external broadcastReward(noId) {
        module.proposeNodeOperatorRewardAddressChange(noId, rewardAddress);
    }

    function confirmManagerAddress(uint256 noId) external broadcastProposedManager(noId) {
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function confirmRewardAddress(uint256 noId) external broadcastProposedReward(noId) {
        module.confirmNodeOperatorRewardAddressChange(noId);
    }

    function addKeys(uint256 noId, uint256 keysCount) external broadcastManager(noId) {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        seed = keccak256(abi.encodePacked(block.prevrandao, block.timestamp, noId));
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        address manager = module.getNodeOperator(noId).managerAddress;
        module.addValidatorKeysETH{ value: amount }(manager, noId, keysCount, keys, signatures);
    }

    function deposit(uint256 depositCount) external broadcastStakingRouter {
        module.batchDepositInfoUpdate(type(uint256).max);

        (, , uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        if (depositCount > depositableValidatorsCount) depositCount = depositableValidatorsCount;
        (, uint256 totalDepositedValidators, ) = module.getStakingModuleSummary();

        module.obtainDepositData(depositCount, "");

        (, uint256 totalDepositedValidatorsAfter, ) = module.getStakingModuleSummary();
        // assertEq(totalDepositedValidatorsAfter, totalDepositedValidators + depositCount);
    }

    function removeKey(uint256 noId, uint256 keyIndex) external broadcastManager(noId) {
        module.removeKeys(noId, keyIndex, 1);
    }

    function unvet(uint256 noId, uint256 newVettedKeysCount) external broadcastStakingRouter {
        module.decreaseVettedSigningKeysCount(_encodeNodeOperatorId(noId), _encodeUint128Value(newVettedKeysCount));

        assertEq(module.getNodeOperator(noId).totalVettedKeys, newVettedKeysCount);
    }

    function exit(uint256 noId, uint256 exitedKeysCount) external broadcastStakingRouter {
        module.updateExitedValidatorsCount(_encodeNodeOperatorId(noId), _encodeUint128Value(exitedKeysCount));

        assertEq(module.getNodeOperator(noId).totalExitedKeys, exitedKeysCount);
    }

    function slash(uint256 noId, uint256 keyIndex) external broadcastVerifier {
        module.reportValidatorSlashing(noId, keyIndex);
    }

    function withdraw(
        uint256 noId,
        uint256 keyIndex,
        uint256 exitBalance,
        uint256 slashingPenalty
    ) external broadcastVerifier {
        uint256 withdrawnBefore = module.getNodeOperator(noId).totalWithdrawnKeys;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo(noId, keyIndex, exitBalance, slashingPenalty, slashingPenalty > 0);
        module.reportRegularWithdrawnValidators(validatorInfos);

        assertTrue(module.isValidatorWithdrawn(noId, keyIndex));
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, withdrawnBefore + 1);
    }

    function targetLimit(uint256 noId, uint256 targetLimitMode, uint256 limit) external broadcastStakingRouter {
        module.updateTargetValidatorsLimits(noId, targetLimitMode, limit);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.targetLimit, limit);
        assertEq(no.targetLimitMode, targetLimitMode);
    }

    function reportGeneralDelayedPenalty(uint256 noId, uint256 amount) external broadcastPenaltyReporter {
        uint256 lockedBefore = accounting.getLockedBond(noId);

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        uint256 lockedAfter = accounting.getLockedBond(noId);
        assertEq(
            lockedAfter,
            lockedBefore +
                amount +
                module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(accounting.getBondCurveId(noId))
        );
    }

    function cancelGeneralDelayedPenalty(uint256 noId, uint256 amount) external broadcastPenaltyReporter {
        uint256 lockedBefore = accounting.getLockedBond(noId);

        module.cancelGeneralDelayedPenalty(noId, amount);

        uint256 lockedAfter = accounting.getLockedBond(noId);
        assertEq(lockedAfter, lockedBefore - amount);
    }

    function settleGeneralDelayedPenalty(uint256 noId) external broadcastPenaltySettler {
        uint256[] memory noIds = new uint256[](1);
        noIds[0] = noId;
        uint256[] memory maxAmounts = new uint256[](1);
        maxAmounts[0] = type(uint256).max; // Set to max to settle
        module.settleGeneralDelayedPenalty(noIds, maxAmounts);

        assertEq(accounting.getLockedBond(noId), 0);
    }

    function compensateGeneralDelayedPenalty(uint256 noId) external broadcastStranger {
        module.compensateGeneralDelayedPenalty(noId);
    }

    function addBond(uint256 noId, uint256 amount) external broadcastManager(noId) {
        accounting.depositETH{ value: amount }(noId);
    }

    function createBondDebt(uint256 noId, uint256 amount) external broadcastModule {
        accounting.penalize(noId, amount);
    }

    function exitRequest(uint256 noId, uint256 keyIndex, uint256 validatorIndex) public {
        _setUp();
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);
        _exitRequest(noId, validatorIndex, pubkey);
    }

    function _exitRequest(uint256 noId, uint256 validatorIndex, bytes memory validatorPubKey) internal {
        IVEBO vebo = IVEBO(locator.validatorsExitBusOracle());

        bytes3 moduleId = bytes3(uint24(_getModuleId()));
        // Node operator ids stay below 2^40 (queue limit), mirroring production encoding.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes5 nodeOpId = bytes5(uint40(noId));
        // Validator indices are limited by the number of keys in the queue (< 2^32), so 64 bits suffice.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes8 _validatorIndex = bytes8(uint64(validatorIndex));

        (, uint256 refSlot, , ) = vebo.getConsensusReport();
        uint256 reportRefSlot = refSlot + 1;

        bytes memory data = abi.encodePacked(moduleId, nodeOpId, _validatorIndex, validatorPubKey);
        IVEBO.ReportData memory report = IVEBO.ReportData({
            consensusVersion: vebo.getConsensusVersion(),
            refSlot: reportRefSlot,
            requestsCount: 1,
            dataFormat: 1,
            data: data
        });

        address consensus = vebo.getConsensusContract();
        _setBalance(consensus);

        vm.startBroadcast(consensus);
        vebo.submitConsensusReport(keccak256(abi.encode(report)), reportRefSlot, block.timestamp + 1 days);
        vm.stopBroadcast();

        address veboSubmitter = _prepareVEBOSubmitter(vebo);
        vm.startBroadcast(veboSubmitter);
        vebo.submitReportData(report, vebo.getContractVersion());
        vm.stopBroadcast();
    }

    function _prepareVEBOSubmitter(IVEBO vebo) internal returns (address veboSubmitter) {
        address veboAdmin = _prepareAdmin(address(vebo));
        veboSubmitter = nextAddress();

        vm.startBroadcast(veboAdmin);
        vebo.grantRole(vebo.SUBMIT_DATA_ROLE(), address(veboSubmitter));
        vm.stopBroadcast();

        _setBalance(address(veboSubmitter));
    }

    function activateKeys(uint256 noId, uint256 count) external broadcastVerifier {
        NodeOperator memory no = module.getNodeOperator(noId);
        uint256 activated;
        for (uint256 i; i < no.totalDepositedKeys && activated < count; ++i) {
            if (module.getKeyConfirmedBalances(noId, i, 1)[0] == 0 && !module.isValidatorWithdrawn(noId, i)) {
                module.reportValidatorBalance(noId, i, 32 ether + 1 gwei);
                ++activated;
            }
        }
        assertEq(activated, count, "not enough deposited keys to activate");
    }

    function reportBalance(uint256 noId, uint256 keyIndex, uint256 balanceWei) external broadcastVerifier {
        require(keyIndex < module.getNodeOperator(noId).totalDepositedKeys, "key index out of bounds");
        require(!module.isValidatorWithdrawn(noId, keyIndex), "key is withdrawn");
        module.reportValidatorBalance(noId, keyIndex, balanceWei);
    }

    function increaseAllocatedBalance(
        uint256 noId,
        uint256 keyIndex,
        uint256 amountWei
    ) external broadcastStakingRouter {
        require(keyIndex < module.getNodeOperator(noId).totalDepositedKeys, "key index out of bounds");
        require(!module.isValidatorWithdrawn(noId, keyIndex), "key is withdrawn");

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = module.getSigningKeys(noId, keyIndex, 1);

        uint256[] memory keyIndices = new uint256[](1);
        keyIndices[0] = keyIndex;

        uint256[] memory operatorIds = new uint256[](1);
        operatorIds[0] = noId;

        uint256[] memory topUpLimits = new uint256[](1);
        topUpLimits[0] = amountWei;

        module.allocateDeposits(amountWei, pubkeys, keyIndices, operatorIds, topUpLimits);
    }

    uint256 internal constant MAX_TOPUP_PER_KEY = 2016 ether;

    function topUpActiveKeys(uint256 noId) external broadcastStakingRouter {
        NodeOperator memory no = module.getNodeOperator(noId);
        uint256 total = no.totalDepositedKeys;
        require(total > 0, "no deposited keys");

        uint256[] memory allocated = module.getKeyAllocatedBalances(noId, 0, total);

        // Process strictly in key-index order; TopUpQueueOps enforces a
        // global FIFO queue head, so we match it one entry at a time via
        // single-key calls (same shape as increaseAllocatedBalance).
        uint256 topped;
        for (uint256 i; i < total; ++i) {
            if (allocated[i] != 0) continue;
            if (module.isValidatorWithdrawn(noId, i)) continue;

            bytes[] memory pubkeys = new bytes[](1);
            pubkeys[0] = module.getSigningKeys(noId, i, 1);

            uint256[] memory keyIndices = new uint256[](1);
            keyIndices[0] = i;

            uint256[] memory operatorIds = new uint256[](1);
            operatorIds[0] = noId;

            uint256[] memory topUpLimits = new uint256[](1);
            topUpLimits[0] = MAX_TOPUP_PER_KEY;

            module.allocateDeposits(MAX_TOPUP_PER_KEY, pubkeys, keyIndices, operatorIds, topUpLimits);
            unchecked {
                ++topped;
            }
        }
        console.log("topped up keys:", topped);
    }

    function createCuratedOperator(uint256 gateIndex, uint256 keysCount, address operator) public {
        _setUp();
        if (operator == address(0)) operator = nextAddress("curated-operator");

        CuratedGate gate = CuratedGate(curatedGates[gateIndex]);
        bytes32 origRoot = gate.treeRoot();
        string memory origCid = gate.treeCid();
        address admin = gate.getRoleMember(gate.DEFAULT_ADMIN_ROLE(), 0);
        _setBalance(admin);
        _setBalance(operator);

        bytes32[] memory proof = _setTempTree(gate, admin, operator);

        uint256 noId = _createViaGate(gate, operator, proof);

        if (keysCount > 0) {
            _addKeysForOperator(operator, noId, keysCount);
        }

        // Restore original tree params
        vm.startBroadcast(admin);
        gate.setTreeParams(origRoot, origCid);
        vm.stopBroadcast();
    }

    function _setTempTree(CuratedGate gate, address admin, address operator) internal returns (bytes32[] memory proof) {
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(operator));
        address extra = nextAddress("curated-proof-extra");
        tree.pushLeaf(abi.encode(extra));
        proof = tree.getProof(0);
        string memory tmpCid = string.concat("tmp-cid-", vm.toString(uint256(uint160(extra))));

        vm.startBroadcast(admin);
        gate.grantRole(gate.SET_TREE_ROLE(), admin);
        gate.grantRole(gate.RESUME_ROLE(), admin);
        if (gate.isPaused()) gate.resume();
        gate.setTreeParams(tree.root(), tmpCid);
        vm.stopBroadcast();
    }

    function _createViaGate(
        CuratedGate gate,
        address operator,
        bytes32[] memory proof
    ) internal returns (uint256 noId) {
        vm.startBroadcast(operator);
        noId = gate.createNodeOperator("fork-operator", "fork-test", address(0), address(0), proof);
        vm.stopBroadcast();
        console.log("noId", noId);
    }

    function _addKeysForOperator(address operator, uint256 noId, uint256 keysCount) internal {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        _setBalance(operator, amount + 1 ether);

        vm.startBroadcast(operator);
        module.addValidatorKeysETH{ value: amount }(
            operator,
            noId,
            keysCount,
            randomBytes(48 * keysCount),
            randomBytes(96 * keysCount)
        );
        vm.stopBroadcast();
    }

    function operatorsCount() external {
        _setUp();
        console.log(vm.toString(module.getNodeOperatorsCount()));
    }

    function operatorKey(uint256 noId, uint256 keyIndex) external {
        _setUp();
        bytes memory key = module.getSigningKeys(noId, keyIndex, 1);
        console.log(vm.toString(key));
    }

    function operatorKeys(uint256 noId) external {
        _setUp();
        NodeOperator memory no = module.getNodeOperator(noId);
        if (no.totalAddedKeys == 0) return;
        console.log(string.concat(_pad("id", 4), " ", "pubkey"));
        bytes memory keys = module.getSigningKeys(noId, 0, no.totalAddedKeys);
        for (uint256 i; i < no.totalAddedKeys; ++i) {
            bytes memory key = new bytes(48);
            for (uint256 j; j < 48; ++j) key[j] = keys[i * 48 + j];
            console.log(string.concat(_pad(vm.toString(i), 4), " ", vm.toString(key)));
        }
    }

    function operatorInfo(uint256 noId) external {
        _setUp();
        NodeOperator memory no = module.getNodeOperator(noId);
        console.log(
            string.concat(
                _col("totalAddedKeys", no.totalAddedKeys),
                _col("depositableValidators", no.depositableValidatorsCount)
            )
        );
        console.log(
            string.concat(_col("totalVettedKeys", no.totalVettedKeys), _col("enqueuedCount", no.enqueuedCount))
        );
        console.log(
            string.concat(
                _col("totalDepositedKeys", no.totalDepositedKeys),
                _col("stuckValidatorsCount", no.stuckValidatorsCount)
            )
        );
        console.log(
            string.concat(
                _col("totalWithdrawnKeys", no.totalWithdrawnKeys),
                _col("targetLimitMode", no.targetLimitMode)
            )
        );
        console.log(string.concat(_col("totalExitedKeys", no.totalExitedKeys), _col("targetLimit", no.targetLimit)));
        console.log(string.concat(_pad("extendedManagerPerms", 24), no.extendedManagerPermissions ? "true" : "false"));
        console.log(string.concat(_pad("managerAddress", 24), vm.toString(no.managerAddress)));
        console.log(string.concat(_pad("proposedManagerAddress", 24), vm.toString(no.proposedManagerAddress)));
        console.log(string.concat(_pad("rewardAddress", 24), vm.toString(no.rewardAddress)));
        console.log(string.concat(_pad("proposedRewardAddress", 24), vm.toString(no.proposedRewardAddress)));
    }

    function bondInfo(uint256 noId) external {
        _setUp();
        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(noId);
        console.log(string.concat(_pad("currentBond", 24), vm.toString(info.currentBond)));
        console.log(string.concat(_pad("requiredBond", 24), vm.toString(info.requiredBond)));
        console.log(string.concat(_pad("lockedBond", 24), vm.toString(info.lockedBond)));
        console.log(string.concat(_pad("bondDebt", 24), vm.toString(info.bondDebt)));
        console.log(string.concat(_pad("pendingSharesToSplit", 24), vm.toString(info.pendingSharesToSplit)));
    }

    function keyAllocatedBalance(uint256 noId, uint256 keyIndex) external {
        _setUp();
        uint256[] memory balances = module.getKeyAllocatedBalances(noId, keyIndex, 1);
        console.log(vm.toString(balances[0] / 1 ether));
    }

    function keyAllocatedBalances(uint256 noId) external {
        _setUp();
        NodeOperator memory no = module.getNodeOperator(noId);
        if (no.totalDepositedKeys == 0) return;
        uint256[] memory balances = module.getKeyAllocatedBalances(noId, 0, no.totalDepositedKeys);
        console.log(string.concat(_pad("id", 4), " ", "allocated (ETH)"));
        for (uint256 i; i < no.totalDepositedKeys; ++i) {
            console.log(string.concat(_pad(vm.toString(i), 4), " ", vm.toString(balances[i] / 1 ether)));
        }
    }

    error NodeOperatorsModuleNotFound();

    function _col(string memory label, uint256 val) internal pure returns (string memory) {
        return string.concat(_pad(label, 24), _pad(vm.toString(val), 6));
    }

    function _pad(string memory s, uint256 w) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length >= w) return s;
        bytes memory r = new bytes(w);
        for (uint256 i; i < b.length; ++i) r[i] = b[i];
        for (uint256 i = b.length; i < w; ++i) r[i] = " ";
        return string(r);
    }

    function _getModuleId() internal view returns (uint256) {
        uint256[] memory ids = stakingRouter.getStakingModuleIds();
        for (uint256 i = ids.length - 1; i > 0; i--) {
            IStakingRouter.StakingModule memory moduleInfo = stakingRouter.getStakingModule(ids[i]);
            if (moduleInfo.stakingModuleAddress == address(module)) return ids[i];
        }
        revert NodeOperatorsModuleNotFound();
    }
}
