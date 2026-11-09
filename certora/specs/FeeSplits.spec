/*
 * Scope: the actual FeeSplits implementation, with internal mutators exposed by
 * FeeSplitsHarness. No token model or external-call summaries are used.
 *
 * These are transition properties, not a proof of Accounting's complete reward
 * claim flow. The pre-state bound splitCount(id) <= 10 is the reachable validated
 * configuration bound on Solidity's old-array deletion. In solc 0.8.33 legacy
 * optimized bytecode, deletion loops over 2 * oldLength storage words with a
 * stride of 2, clearing both fields each iteration: at most 10 body iterations
 * and 11 header checks. loop_iter=11 conservatively budgets the final guard;
 * backend unwind assertions still need an actual Prover run.
 * Each post-update rule executes the real validator before observing payouts.
 * Payout totality is scoped to amount <= max_uint256 / 10000: the production
 * multiplication is checked and larger symbolic values may legitimately revert.
 * Empty arrays, duplicate recipients, and recipient == currentContract are valid.
 * Pending shares include the operator's retained remainder, not just payouts.
 * Namespaced storage is observed only through Solidity getters. No direct CVL
 * storage access or extension layout is used. Backend storage/memory analysis
 * must still be checked on the first server run; local typechecking is not proof.
 */
methods {
    function updateSplits(uint256, IFeeSplits.FeeSplit[], address) external;
    function increasePending(uint256, uint256) external;
    function decreasePending(uint256, uint256) external;
    function getPendingSharesToSplit(uint256) external returns (uint256) envfree;
    function hasSplits(uint256) external returns (bool) envfree;
    function splitCount(uint256) external returns (uint256) envfree;
    function splitAt(uint256, uint256) external returns (address, uint256) envfree;
    function splitShareSum(uint256) external returns (uint256) envfree;
    function transferCount(uint256, uint256) external returns (uint256) envfree;
    function transferAt(uint256, uint256, uint256) external returns (address, uint256) envfree;
    function transferSum(uint256, uint256) external returns (uint256) envfree;
}

rule increasePendingExact(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0;
    uint256 before = getPendingSharesToSplit(id);
    require before + amount <= max_uint256;
    increasePending@withrevert(e, id, amount);
    assert !lastReverted;
    assert getPendingSharesToSplit(id) == before + amount;
}

rule decreasePendingExact(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0;
    uint256 before = getPendingSharesToSplit(id);
    require amount <= before;
    decreasePending@withrevert(e, id, amount);
    assert !lastReverted;
    assert getPendingSharesToSplit(id) == before - amount;
}

rule pendingCreditOverflowReverts(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0;
    require getPendingSharesToSplit(id) + amount > max_uint256;
    increasePending@withrevert(e, id, amount);
    assert lastReverted;
}

rule excessiveDebitReverts(env e, uint256 id, uint256 amount) {
    require amount > getPendingSharesToSplit(id);
    decreasePending@withrevert(e, id, amount);
    assert lastReverted;
}

rule pendingCreditDoesNotAffectAnotherOperator(env e, uint256 id, uint256 other, uint256 amount) {
    require id != other;
    uint256 before = getPendingSharesToSplit(other);
    increasePending(e, id, amount);
    assert getPendingSharesToSplit(other) == before;
}

rule pendingDebitDoesNotAffectAnotherOperator(env e, uint256 id, uint256 other, uint256 amount) {
    require id != other;
    uint256 before = getPendingSharesToSplit(other);
    decreasePending(e, id, amount);
    assert getPendingSharesToSplit(other) == before;
}

rule pendingSharesBlockConfiguration(env e, uint256 id, address stETH) {
    IFeeSplits.FeeSplit[] splits;
    require getPendingSharesToSplit(id) > 0;
    updateSplits@withrevert(e, id, splits, stETH);
    assert lastReverted;
}

rule tooManyRecipientsRevert(env e, uint256 id, address stETH) {
    IFeeSplits.FeeSplit[] splits;
    require splits.length > 10;
    updateSplits@withrevert(e, id, splits, stETH);
    assert lastReverted;
}

rule updateEstablishesRecipientCountAndBudget(env e, uint256 id, address stETH) {
    IFeeSplits.FeeSplit[] splits;
    require splitCount(id) <= 10;
    updateSplits(e, id, splits, stETH);
    assert splitCount(id) == splits.length;
    assert splitCount(id) <= 10;
    assert splitShareSum(id) <= 10000;
    assert hasSplits(id) == (splits.length > 0);
    assert getPendingSharesToSplit(id) == 0;
}

rule updateStoresEveryEntry(env e, uint256 id, address stETH, uint256 index) {
    IFeeSplits.FeeSplit[] splits;
    require splitCount(id) <= 10;
    require index < splits.length;
    updateSplits(e, id, splits, stETH);
    address recipient; uint256 share;
    recipient, share = splitAt(id, index);
    assert recipient == splits[index].recipient;
    assert share == splits[index].share;
    assert recipient != 0 && recipient != stETH;
    assert share > 0;
}

rule configurationDoesNotAffectAnotherOperator(env e, uint256 id, uint256 other, address stETH) {
    IFeeSplits.FeeSplit[] splits;
    require id != other;
    require splitCount(id) <= 10;
    uint256 countBefore = splitCount(other);
    uint256 pendingBefore = getPendingSharesToSplit(other);
    updateSplits(e, id, splits, stETH);
    assert splitCount(other) == countBefore;
    assert getPendingSharesToSplit(other) == pendingBefore;
}

rule configurationDoesNotChangeAnotherOperatorsEntry(
    env e, uint256 id, uint256 other, address stETH, uint256 index
) {
    IFeeSplits.FeeSplit[] splits;
    require id != other;
    require splitCount(id) <= 10;
    require index < splitCount(other);
    address recipientBefore; uint256 shareBefore;
    recipientBefore, shareBefore = splitAt(other, index);
    updateSplits(e, id, splits, stETH);
    address recipientAfter; uint256 shareAfter;
    recipientAfter, shareAfter = splitAt(other, index);
    assert recipientAfter == recipientBefore;
    assert shareAfter == shareBefore;
}

rule validSingletonConfigurationSucceeds(env e, uint256 id, address stETH) {
    IFeeSplits.FeeSplit[] splits;
    require e.msg.value == 0;
    require splitCount(id) <= 10;
    require getPendingSharesToSplit(id) == 0;
    require splits.length == 1;
    require splits[0].recipient != 0 && splits[0].recipient != stETH;
    require splits[0].share > 0 && splits[0].share <= 10000;
    updateSplits@withrevert(e, id, splits, stETH);
    assert !lastReverted;
    assert splitCount(id) == 1;
}

rule payoutsStayWithinBudget(env e, uint256 id, address stETH, uint256 amount) {
    IFeeSplits.FeeSplit[] splits;
    require splitCount(id) <= 10;
    require amount <= max_uint256 / 10000;
    updateSplits(e, id, splits, stETH);
    uint256 paid = transferSum@withrevert(id, amount);
    assert !lastReverted;
    assert paid <= amount;
    assert transferCount(id, amount) == (amount == 0 ? 0 : splits.length);
}

rule eachPayoutUsesConfiguredRecipientAndFloor(
    env e, uint256 id, address stETH, uint256 amount, uint256 index
) {
    IFeeSplits.FeeSplit[] splits;
    require splitCount(id) <= 10;
    require index < splits.length;
    require amount > 0 && amount <= max_uint256 / 10000;
    updateSplits(e, id, splits, stETH);
    address recipient; uint256 shares;
    recipient, shares = transferAt(id, amount, index);
    assert recipient == splits[index].recipient;
    assert shares == amount * splits[index].share / 10000;
}

rule fullSplitLeavesOnlyRoundingDust(env e, uint256 id, address stETH, uint256 amount) {
    IFeeSplits.FeeSplit[] splits;
    require splitCount(id) <= 10;
    require amount <= max_uint256 / 10000;
    updateSplits(e, id, splits, stETH);
    require splitShareSum(id) == 10000;
    uint256 paid = transferSum(id, amount);
    assert paid <= amount;
    assert amount - paid < splitCount(id);
}

rule zeroAmountProducesNoTransfers(uint256 id) {
    assert transferCount(id, 0) == 0;
    assert transferSum(id, 0) == 0;
}
