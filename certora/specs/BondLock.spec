// BondLock primitive correctness. This scene has no external dependencies or loop summaries.
// Calls begin from arbitrary storage. Rules explicitly constrain the pre-state where needed.
// Authorization, penalty settlement and Accounting's nonce comparison are outside this scene.
// Storage is observed through production getters, not CVL direct storage access. No synthetic
// storage extensions are added; backend storage/memory analysis still requires a Prover run.
methods {
    function getBondLockPeriod() external returns (uint256) envfree;
    function MIN_BOND_LOCK_PERIOD() external returns (uint256) envfree;
    function MAX_BOND_LOCK_PERIOD() external returns (uint256) envfree;
    function getLockedBond(uint256) external returns (uint256) envfree;
    function getBondLockNonce(uint256) external returns (uint256) envfree;
    function lockUntil(uint256) external returns (uint256) envfree;
}

rule periodUpdateWritesExactValue(env e, uint256 period) {
    require e.msg.value == 0;
    require period >= MIN_BOND_LOCK_PERIOD() && period <= MAX_BOND_LOCK_PERIOD();
    setPeriod@withrevert(e, period);
    assert !lastReverted;
    assert getBondLockPeriod() == period;
}

rule invalidPeriodReverts(env e, uint256 period) {
    require period < MIN_BOND_LOCK_PERIOD() || period > MAX_BOND_LOCK_PERIOD();
    setPeriod@withrevert(e, period);
    assert lastReverted;
}

rule periodUpdatePreservesExistingLock(env e, uint256 id, uint256 period) {
    uint256 amount = getLockedBond(id);
    uint256 until = lockUntil(id);
    uint256 nonce = getBondLockNonce(id);
    setPeriod(e, period);
    assert getLockedBond(id) == amount;
    assert lockUntil(id) == until;
    assert getBondLockNonce(id) == nonce;
}

rule liveLockAccumulatesAmount(env e, uint256 id, uint256 amount) {
    require lockUntil(id) > e.block.timestamp;
    mathint oldAmount = getLockedBond(id);
    lock(e, id, amount);
    assert to_mathint(getLockedBond(id)) == oldAmount + amount;
}

rule expiredOrAbsentLockReplacesAmount(env e, uint256 id, uint256 amount) {
    require lockUntil(id) <= e.block.timestamp;
    lock(e, id, amount);
    assert getLockedBond(id) == amount;
}

rule lockDeadlineIsMaximum(env e, uint256 id, uint256 amount) {
    mathint oldUntil = lockUntil(id);
    mathint deadline = to_mathint(e.block.timestamp) + getBondLockPeriod();
    lock(e, id, amount);
    assert to_mathint(lockUntil(id)) == (oldUntil > deadline ? oldUntil : deadline);
}

rule lockIncrementsNonceModuloUint256(env e, uint256 id, uint256 amount) {
    mathint oldNonce = getBondLockNonce(id);
    lock(e, id, amount);
    assert to_mathint(getBondLockNonce(id)) == (oldNonce == max_uint256 ? 0 : oldNonce + 1);
}

rule representableLockSucceeds(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0;
    require amount > 0;
    require getBondLockPeriod() >= MIN_BOND_LOCK_PERIOD();
    require getBondLockPeriod() <= MAX_BOND_LOCK_PERIOD();
    require to_mathint(e.block.timestamp) + getBondLockPeriod() <= max_uint128;
    mathint effectiveAmount = lockUntil(id) > e.block.timestamp ? to_mathint(getLockedBond(id)) + amount : amount;
    require effectiveAmount <= max_uint128;
    lock@withrevert(e, id, amount);
    assert !lastReverted;
}

rule zeroLockReverts(env e, uint256 id) {
    lock@withrevert(e, id, 0);
    assert lastReverted;
}

rule oversizedLockReverts(env e, uint256 id, uint256 amount) {
    mathint oldAmount = getLockedBond(id);
    mathint effectiveAmount = lockUntil(id) > e.block.timestamp ? oldAmount + amount : amount;
    require effectiveAmount > max_uint128;
    lock@withrevert(e, id, amount);
    assert lastReverted;
}

rule lockPreservesOtherOperators(env e, uint256 id, uint256 other, uint256 amount) {
    require id != other;
    uint256 otherAmount = getLockedBond(other);
    uint256 otherUntil = lockUntil(other);
    uint256 otherNonce = getBondLockNonce(other);
    lock(e, id, amount);
    assert getLockedBond(other) == otherAmount;
    assert lockUntil(other) == otherUntil;
    assert getBondLockNonce(other) == otherNonce;
}

rule partialUnlockPreservesDeadlineAndNonce(env e, uint256 id, uint256 amount) {
    require e.msg.value == 0;
    mathint oldAmount = getLockedBond(id);
    require amount > 0 && amount < oldAmount;
    uint256 until = lockUntil(id);
    uint256 nonce = getBondLockNonce(id);
    unlock@withrevert(e, id, amount);
    assert !lastReverted;
    assert to_mathint(getLockedBond(id)) == oldAmount - amount;
    assert lockUntil(id) == until;
    assert getBondLockNonce(id) == nonce;
}

rule fullUnlockClearsLockAndPreservesNonce(env e, uint256 id) {
    require e.msg.value == 0;
    uint256 amount = getLockedBond(id);
    require amount > 0;
    uint256 nonce = getBondLockNonce(id);
    unlock@withrevert(e, id, amount);
    assert !lastReverted;
    assert getLockedBond(id) == 0;
    assert lockUntil(id) == 0;
    assert getBondLockNonce(id) == nonce;
}

rule invalidUnlockReverts(env e, uint256 id, uint256 amount) {
    require amount == 0 || amount > getLockedBond(id);
    unlock@withrevert(e, id, amount);
    assert lastReverted;
}

rule expiryUsesInclusiveDeadline(env e, uint256 id) {
    uint256 until = lockUntil(id);
    bool expired = isLockExpired(e, id);
    assert expired == (until != 0 && until <= e.block.timestamp);
}

rule expiredLockCleanupSucceeds(env e, uint256 id) {
    require e.msg.value == 0;
    require getLockedBond(id) > 0;
    require lockUntil(id) > 0 && lockUntil(id) <= e.block.timestamp;
    uint256 nonce = getBondLockNonce(id);
    unlockExpired@withrevert(e, id);
    assert !lastReverted;
    assert getLockedBond(id) == 0;
    assert lockUntil(id) == 0;
    assert getBondLockNonce(id) == nonce;
}

rule absentOrLiveLockCannotBeCleaned(env e, uint256 id) {
    require getLockedBond(id) == 0 || lockUntil(id) == 0 || lockUntil(id) > e.block.timestamp;
    unlockExpired@withrevert(e, id);
    assert lastReverted;
}

rule unlockPreservesOtherOperators(env e, uint256 id, uint256 other, uint256 amount) {
    require id != other;
    uint256 otherAmount = getLockedBond(other);
    uint256 otherUntil = lockUntil(other);
    uint256 otherNonce = getBondLockNonce(other);
    unlock(e, id, amount);
    assert getLockedBond(other) == otherAmount;
    assert lockUntil(other) == otherUntil;
    assert getBondLockNonce(other) == otherNonce;
}

rule initializationCannotRepeat(env e, uint256 period) {
    initialize(e, period);
    initialize@withrevert(e, period);
    assert lastReverted;
}
