// Transition properties for the real FeeDistributor implementation.
//
// Scope: one-sibling Merkle proofs; report CID strings (old and new) <= 64 bytes,
// covering common 46/59-byte IPFS encodings. Loop-unwind obligations remain active.
// The overwritten history entry's old CIDs are also bounded to 64 bytes. A full
// append-only invariant establishing that this entry is empty is out of scope.
// No rule asserts correctness for arbitrary proof depth or arbitrary CID length.
// Token assumption: exact shares, no callbacks, modeled by FeeTokenModel.
// Arbitrary pre-state is used with each rule's stated preconditions. Proxy
// initialization/migration and a protocol-wide inductive invariant are not proved.

using FeeTokenModel as token;

methods {
    function STETH() external returns (address) envfree;
    function RECOVERER_ROLE() external returns (bytes32) envfree;
    function hasRole(bytes32,address) external returns (bool) envfree;
    function ACCOUNTING() external returns (address) envfree;
    function ORACLE() external returns (address) envfree;
    function treeRoot() external returns (bytes32) envfree;
    function rebateRecipient() external returns (address) envfree;
    function distributedShares(uint256) external returns (uint256) envfree;
    function totalClaimableShares() external returns (uint256) envfree;
    function distributionDataHistoryCount() external returns (uint256) envfree;
    function pendingSharesToDistribute() external returns (uint256) envfree;
    function rootForOneSibling(uint256,uint256,bytes32) external returns (bytes32) envfree;
    function treeCidLength() external returns (uint256) envfree;
    function logCidLength() external returns (uint256) envfree;
    function historyRefSlot(uint256) external returns (uint256) envfree;
    function historyTreeRoot(uint256) external returns (bytes32) envfree;
    function historyDistributed(uint256) external returns (uint256) envfree;
    function historyRebate(uint256) external returns (uint256) envfree;
    function historyTreeCidLength(uint256) external returns (uint256) envfree;
    function historyLogCidLength(uint256) external returns (uint256) envfree;
    function token.sharesOf(address) external returns (uint256) envfree;
}

function validDistributionInput(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    require e.msg.value == 0;
    require e.msg.sender == ACCOUNTING();
    require proof.length == 1;
    require treeRoot() == rootForOneSibling(id, cumulative, proof[0]);
}

function boundedReportInput(env e, string newTreeCid, string newLogCid) {
    require e.msg.value == 0;
    require e.msg.sender == ORACLE();
    require treeCidLength() <= 64 && logCidLength() <= 64;
    require newTreeCid.length <= 64 && newLogCid.length <= 64;
    uint256 count = distributionDataHistoryCount();
    require historyTreeCidLength(count) <= 64 && historyLogCidLength(count) <= 64;
}

rule distributionUsesExactCumulativeDelta(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    mathint before = distributedShares(id);
    mathint claimableBefore = totalClaimableShares();
    uint256 paid = distributeFees(e, id, cumulative, proof);
    assert paid == cumulative - before;
    assert distributedShares(id) == cumulative;
    assert totalClaimableShares() == claimableBefore - paid;
}

rule distributionMovesExactShares(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    address accounting = ACCOUNTING();
    mathint senderBefore = token.sharesOf(currentContract);
    mathint recipientBefore = token.sharesOf(accounting);
    uint256 paid = distributeFees(e, id, cumulative, proof);
    assert token.sharesOf(currentContract) == (accounting == currentContract ? senderBefore : senderBefore - paid);
    assert token.sharesOf(accounting) == (accounting == currentContract ? recipientBefore : recipientBefore + paid);
}

rule distributionPreservesFunding(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    require token.sharesOf(currentContract) >= totalClaimableShares();
    distributeFees(e, id, cumulative, proof);
    assert token.sharesOf(currentContract) >= totalClaimableShares();
}

rule distributionIsOperatorLocal(env e, uint256 id, uint256 other, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    require id != other;
    uint256 before = distributedShares(other);
    distributeFees(e, id, cumulative, proof);
    assert distributedShares(other) == before;
}

rule repeatedCumulativeClaimPaysZero(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    distributeFees(e, id, cumulative, proof);
    uint256 claimable = totalClaimableShares();
    uint256 shares = token.sharesOf(currentContract);
    uint256 repeated = distributeFees(e, id, cumulative, proof);
    assert repeated == 0;
    assert totalClaimableShares() == claimable;
    assert token.sharesOf(currentContract) == shares;
}

rule decreasingCumulativeClaimReverts(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    require distributedShares(id) > cumulative;
    distributeFees@withrevert(e, id, cumulative, proof);
    assert lastReverted;
}

rule unfundedDistributionReverts(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    require cumulative >= distributedShares(id);
    require cumulative - distributedShares(id) > totalClaimableShares();
    distributeFees@withrevert(e, id, cumulative, proof);
    assert lastReverted;
}

rule distributionRequiresAccounting(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    require e.msg.value == 0;
    require proof.length <= 1;
    require e.msg.sender != ACCOUNTING();
    distributeFees@withrevert(e, id, cumulative, proof);
    assert lastReverted;
}

rule emptyProofIsRejected(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    require e.msg.value == 0;
    require proof.length == 0;
    getFeesToDistribute@withrevert(e, id, cumulative, proof);
    assert lastReverted;
}

rule nonemptyProofMustReachCommittedRoot(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    require e.msg.value == 0;
    require proof.length == 1;
    require treeRoot() != rootForOneSibling(id, cumulative, proof[0]);
    getFeesToDistribute@withrevert(e, id, cumulative, proof);
    assert lastReverted;
}

rule oracleReportRequiresOracle(env e, bytes32 root, uint256 distributed, uint256 rebate, uint256 refSlot) {
    require e.msg.value == 0;
    require e.msg.sender != ORACLE();
    processOracleReport@withrevert(e, root, "tree", "log", distributed, rebate, refSlot);
    assert lastReverted;
}

rule oracleReportPreservesFunding(
    env e, bytes32 root, string newTreeCid, string newLogCid, uint256 distributed, uint256 rebate, uint256 refSlot
) {
    boundedReportInput(e, newTreeCid, newLogCid);
    mathint claimableBefore = totalClaimableShares();
    processOracleReport(e, root, newTreeCid, newLogCid, distributed, rebate, refSlot);
    assert totalClaimableShares() == claimableBefore + distributed;
    assert token.sharesOf(currentContract) >= totalClaimableShares();
}

rule oracleReportTransfersOnlyRebate(
    env e, bytes32 root, string newTreeCid, string newLogCid, uint256 distributed, uint256 rebate, uint256 refSlot
) {
    boundedReportInput(e, newTreeCid, newLogCid);
    address recipient = rebateRecipient();
    mathint senderBefore = token.sharesOf(currentContract);
    mathint recipientBefore = token.sharesOf(recipient);
    processOracleReport(e, root, newTreeCid, newLogCid, distributed, rebate, refSlot);
    assert token.sharesOf(currentContract) == (recipient == currentContract ? senderBefore : senderBefore - rebate);
    assert token.sharesOf(recipient) == (recipient == currentContract ? recipientBefore : recipientBefore + rebate);
}

rule oracleReportAppendsExactHistory(
    env e, bytes32 root, string newTreeCid, string newLogCid, uint256 distributed, uint256 rebate, uint256 refSlot
) {
    boundedReportInput(e, newTreeCid, newLogCid);
    uint256 count = distributionDataHistoryCount();
    require count < max_uint256;
    processOracleReport(e, root, newTreeCid, newLogCid, distributed, rebate, refSlot);
    assert distributionDataHistoryCount() == count + 1;
    assert historyRefSlot(count) == refSlot;
    assert historyTreeRoot(count) == treeRoot();
    assert historyDistributed(count) == distributed;
    assert historyRebate(count) == rebate;
}

rule oracleReportCannotOvercommit(
    env e, bytes32 root, string newTreeCid, string newLogCid, uint256 distributed, uint256 rebate, uint256 refSlot
) {
    boundedReportInput(e, newTreeCid, newLogCid);
    require totalClaimableShares() + to_mathint(distributed) + rebate > token.sharesOf(currentContract);
    processOracleReport@withrevert(e, root, newTreeCid, newLogCid, distributed, rebate, refSlot);
    assert lastReverted;
}

rule emptyReportCannotChangeRoot(env e, bytes32 root, string newTreeCid, string newLogCid, uint256 rebate, uint256 refSlot) {
    boundedReportInput(e, newTreeCid, newLogCid);
    bytes32 before = treeRoot();
    processOracleReport(e, root, newTreeCid, newLogCid, 0, rebate, refSlot);
    assert treeRoot() == before;
}

rule stETHCannotBeRecoveredAsERC20(env e, uint256 amount) {
    require e.msg.value == 0;
    require hasRole(RECOVERER_ROLE(), e.msg.sender);
    recoverERC20@withrevert(e, STETH(), amount);
    assert lastReverted;
}

rule pendingSharesAreUncommittedBalance() {
    mathint balance = token.sharesOf(currentContract);
    mathint claimable = totalClaimableShares();
    require balance >= claimable;
    assert pendingSharesToDistribute() == balance - claimable;
}

rule validFundedDistributionDoesNotRevert(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    address accounting = ACCOUNTING();
    require accounting != 0 && accounting != token;
    mathint previous = distributedShares(id);
    require cumulative >= previous;
    mathint delta = cumulative - previous;
    require totalClaimableShares() >= delta;
    require token.sharesOf(currentContract) >= delta;
    require accounting == currentContract || token.sharesOf(accounting) + delta <= max_uint256;
    distributeFees@withrevert(e, id, cumulative, proof);
    assert !lastReverted;
}

rule positiveDistributionIsReachable(env e, uint256 id, uint256 cumulative, bytes32[] proof) {
    validDistributionInput(e, id, cumulative, proof);
    require cumulative > distributedShares(id);
    uint256 paid = distributeFees(e, id, cumulative, proof);
    satisfy paid > 0;
}

rule positiveReportIsReachable(
    env e, bytes32 root, string newTreeCid, string newLogCid, uint256 distributed, uint256 rebate, uint256 refSlot
) {
    boundedReportInput(e, newTreeCid, newLogCid);
    require distributed > 0 && rebate > 0;
    processOracleReport(e, root, newTreeCid, newLogCid, distributed, rebate, refSlot);
    satisfy totalClaimableShares() >= distributed;
}
