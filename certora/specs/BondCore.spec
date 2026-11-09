// Conditional verification of the production BondCore implementation.
// See the executable BondEnvironmentModel for the fixed 3:2 conversion,
// non-reentrancy and dependency-authorization assumptions. These rules do not
// establish Accounting authorization, required bond, proxy initialization,
// global reserve backing, arbitrary exchange rates, or all-operator summation.

methods {
    function totalBondShares() external returns (uint256) envfree;
    function getBondShares(uint256) external returns (uint256) envfree;
    function getBondDebt(uint256) external returns (uint256) envfree;
    function tokenShares(address) external returns (uint256) envfree;
    function sharesByEth(uint256) external returns (uint256) envfree;
    function ethByShares(uint256) external returns (uint256) envfree;
}

// 1. The unchecked credit is mathematical addition only within these bounds.
rule creditDebtFreeUpdatesBothLedgers(env e, uint256 id, uint256 shares) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    require getBondDebt(id) == 0;
    require bond + shares <= max_uint256;
    require total + shares <= max_uint256;
    credit(e, id, shares);
    assert getBondShares(id) == bond + shares;
    assert totalBondShares() == total + shares;
    assert getBondDebt(id) == 0;
}

// 2. Zero incoming shares do not trigger debt coverage or alter the ledgers.
rule zeroCreditIsNoOp(env e, uint256 id) {
    uint256 bond = getBondShares(id);
    uint256 total = totalBondShares();
    uint256 debt = getBondDebt(id);
    credit(e, id, 0);
    assert getBondShares(id) == bond;
    assert totalBondShares() == total;
    assert getBondDebt(id) == debt;
}

// 3. Covering existing debt may consume incoming shares but cannot add debt.
rule creditDoesNotIncreaseDebt(env e, uint256 id, uint256 shares) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    uint256 debt = getBondDebt(id);
    require bond + shares <= max_uint256;
    require total + shares <= max_uint256;
    credit(e, id, shares);
    assert getBondDebt(id) <= debt;
    assert getBondShares(id) <= bond + shares;
    assert totalBondShares() - total == getBondShares(id) - bond;
}

// 4. Per-operator isolation even when the credited operator has existing debt.
rule creditDoesNotChangeAnotherOperator(env e, uint256 id, uint256 other, uint256 shares) {
    require id != other;
    uint256 bond = getBondShares(other);
    uint256 debt = getBondDebt(other);
    credit(e, id, shares);
    assert getBondShares(other) == bond;
    assert getBondDebt(other) == debt;
}

// 5. The internal unsafe debit relies on its caller to establish these bounds.
rule debitUpdatesBothLedgers(env e, uint256 id, uint256 shares) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    uint256 debt = getBondDebt(id);
    require shares <= bond;
    require shares <= total;
    debit(e, id, shares);
    assert getBondShares(id) == bond - shares;
    assert totalBondShares() == total - shares;
    assert getBondDebt(id) == debt;
}

// 6. Charge can remove only min(requested shares, available bond shares).
rule chargeIsCappedByBond(env e, uint256 id, uint256 amount, address to) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint requested = sharesByEth(amount);
    mathint charged = requested < bond ? requested : bond;
    bool success = charge(e, id, amount, to);
    assert getBondShares(id) == bond - charged;
    assert totalBondShares() == total - charged;
    assert success == (charged != 0);
}

// 7. A fee charge never creates penalty debt, including insufficient-bond cases.
rule chargeDoesNotCreateDebt(env e, uint256 id, uint256 amount, address to) {
    uint256 debt = getBondDebt(id);
    charge(e, id, amount, to);
    assert getBondDebt(id) == debt;
}

// 8. Burn is capped by the same share balance independently from its debt result.
rule burnIsCappedByBond(env e, uint256 id, uint256 amount) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint requested = sharesByEth(amount);
    mathint burned = requested < bond ? requested : bond;
    burn(e, id, amount);
    assert getBondShares(id) == bond - burned;
    assert totalBondShares() == total - burned;
}

// 9. Debt is denominated in ETH, and increases by exactly the returned shortage.
//    In particular amount->shares==0 is allowed to return zero (dust behavior).
rule burnAddsOnlyReturnedDebt(env e, uint256 id, uint256 amount) {
    mathint debt = getBondDebt(id);
    uint256 shortage = burn(e, id, amount);
    assert getBondDebt(id) == debt + shortage;
    assert shortage <= amount;
}

// 10. stETH claim honors the caller-supplied share cap; Accounting must establish
//     that this supplied cap itself protects required bond and locks.
rule claimStETHHonorsShareCap(env e, uint256 id, uint256 amount, uint256 claimable, address to) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    uint256 claimed = claimStETH(e, id, amount, claimable, to);
    assert claimed <= claimable;
    assert getBondShares(id) == bond - claimed;
    assert totalBondShares() == total - claimed;
}

// 11. With a distinct recipient, stETH ledger debit equals the actual share exit.
rule claimStETHTransfersExactlyDebitedShares(env e, uint256 id, uint256 amount, uint256 claimable, address to) {
    require to != currentContract;
    mathint balance = tokenShares(currentContract);
    mathint recipient = tokenShares(to);
    uint256 claimed = claimStETH(e, id, amount, claimable, to);
    assert tokenShares(currentContract) == balance - claimed;
    assert tokenShares(to) == recipient + claimed;
}

// 12. wstETH exit records actual shares consumed, including round-trip dust.
rule claimWstETHDebitsActualShares(env e, uint256 id, uint256 amount, uint256 claimable, address to) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint balance = tokenShares(currentContract);
    claimWstETH(e, id, amount, claimable, to);
    mathint debit = balance - tokenShares(currentContract);
    assert debit >= 0;
    assert debit <= claimable;
    assert getBondShares(id) == bond - debit;
    assert totalBondShares() == total - debit;
}

// 13. Withdrawal request submission also records actual shares taken by WQ.
rule claimUnstETHDebitsActualShares(env e, uint256 id, uint256 amount, uint256 claimable, address to) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint balance = tokenShares(currentContract);
    claimUnstETH(e, id, amount, claimable, to);
    mathint debit = balance - tokenShares(currentContract);
    assert debit >= 0;
    assert debit <= claimable;
    assert getBondShares(id) == bond - debit;
    assert totalBondShares() == total - debit;
}

// 14. Incoming ETH with no debt credits exactly the model's minted shares.
rule depositETHCreditsMintedShares(env e, address from, uint256 id) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint minted = sharesByEth(e.msg.value);
    require getBondDebt(id) == 0;
    require bond + minted <= max_uint256;
    require total + minted <= max_uint256;
    depositETH(e, from, id);
    assert getBondShares(id) == bond + minted;
    assert totalBondShares() == total + minted;
}

// 15. stETH deposit uses converted shares, not the raw stETH input amount.
rule depositStETHCreditsTransferredShares(env e, address from, uint256 id, uint256 amount) {
    require from != currentContract;
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint balance = tokenShares(currentContract);
    mathint shares = sharesByEth(amount);
    require getBondDebt(id) == 0;
    require bond + shares <= max_uint256;
    require total + shares <= max_uint256;
    depositStETH(e, from, id, amount);
    assert getBondShares(id) == bond + shares;
    assert totalBondShares() == total + shares;
    assert tokenShares(currentContract) == balance + shares;
}

// 16. Wrapped deposits are credited by the observed unwrap delta.
rule depositWstETHCreditsActualShares(env e, address from, uint256 id, uint256 amount) {
    mathint bond = getBondShares(id);
    mathint total = totalBondShares();
    mathint balance = tokenShares(currentContract);
    require getBondDebt(id) == 0;
    require bond + amount <= max_uint256;
    require total + amount <= max_uint256;
    depositWstETH(e, from, id, amount);
    assert getBondShares(id) == bond + amount;
    assert totalBondShares() == total + amount;
    assert tokenShares(currentContract) == balance + amount;
}

// Positive examples supplement rule_sanity. They ask for a successful nonzero
// flow in the assumed scene, not reachability from initialization or a proof
// that all callers can progress. Model fixture setup remains outside this spec.
rule nonzeroChargeIsPossible(env e, uint256 id, address to) {
    require e.msg.value == 0;
    require to != 0 && to != currentContract;
    require getBondShares(id) >= 2;
    require totalBondShares() >= getBondShares(id);
    require tokenShares(currentContract) >= getBondShares(id);
    bool paid = charge@withrevert(e, id, 3, to);
    satisfy !lastReverted && paid;
}

rule nonzeroBurnIsPossible(env e, uint256 id) {
    require e.msg.value == 0;
    uint256 bond = getBondShares(id);
    require bond >= 2;
    require totalBondShares() >= bond;
    require tokenShares(currentContract) >= bond;
    burn@withrevert(e, id, 3);
    bool reverted = lastReverted;
    satisfy !reverted && getBondShares(id) < bond;
}

rule nonzeroStETHClaimIsPossible(env e, uint256 id, address to) {
    require e.msg.value == 0;
    require to != 0 && to != currentContract;
    require getBondShares(id) >= 2;
    require totalBondShares() >= getBondShares(id);
    require tokenShares(currentContract) >= getBondShares(id);
    uint256 paid = claimStETH@withrevert(e, id, 3, 2, to);
    satisfy !lastReverted && paid > 0;
}

rule nonzeroWstETHClaimIsPossible(env e, uint256 id, address to) {
    require e.msg.value == 0;
    require to != 0 && to != currentContract;
    require getBondShares(id) >= 4;
    require totalBondShares() >= getBondShares(id);
    require tokenShares(currentContract) >= getBondShares(id);
    uint256 paid = claimWstETH@withrevert(e, id, 4, 4, to);
    satisfy !lastReverted && paid > 0;
}

rule nonzeroWithdrawalRequestIsPossible(env e, uint256 id, address to) {
    require e.msg.value == 0;
    require to != 0 && to != currentContract;
    uint256 bond = getBondShares(id);
    require bond >= 4;
    require totalBondShares() >= bond;
    require tokenShares(currentContract) >= bond;
    claimUnstETH@withrevert(e, id, 6, 4, to);
    bool reverted = lastReverted;
    satisfy !reverted && getBondShares(id) < bond;
}
