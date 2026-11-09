# Verification assumptions and limits

All properties are conditional on the scene, linked models, input bounds and
preconditions visible in their `.spec` and `.conf` files. No backend proof has
been inferred from local compilation or Foundry tests.

## Shared trust boundary

- CVL rules generally begin in arbitrary storage states. A positive example is
  not a proof of proxy initialization or migration reachability. No global
  all-operator invariant is established by the current delta rules alone.
- Harnesses inherit production implementations and expose internals or add
  read-only helpers. They are verification-only contracts and must never be
  deployed as protocol implementations. Some internal harness calls deliberately
  bypass public authorization to isolate a primitive's behavior.
- Ordinary CVL calls discard reverting executions. Safety assertions after such
  a call must be read as conditional on success. Totality uses `@withrevert`
  explicitly, including `msg.value == 0` for nonpayable calls and representability
  conditions where needed. `satisfy` checks witness feasibility in the scene.
- Models are non-reentrant. Callback safety, read-only reentrancy and malicious
  dependencies are not proved. Dependency mocks are not substitutes for verified
  production stETH, Burner, WithdrawalQueue or StakingRouter implementations.
- No property covers compromised governance, incorrect oracle content, missing
  off-chain proofs, CL data freshness, gas-bounded progress or transaction
  inclusion. Timing safety is different from eventual execution/liveness.
- No optimistic approximation is enabled in these configs. Loop bounds are
  finite and must be shown adequate by successful pessimistic backend analysis.
  Local CVL typechecking cannot establish their adequacy.
- Cryptographic hashing retains the Prover's standard modeling assumptions.
  This work does not prove Keccak collision resistance or SSZ correctness.
- Getter-based rules avoid synthetic storage extensions. Assembly storage
  recognition and external-call resolution still need backend inspection.

## BondCore

`BondEnvironmentModel.sol` implements floor conversion at a fixed rational
rate of 3 pooled ETH units to 2 shares. This exercises rounding but cannot
establish correctness over arbitrary stETH exchange rates, rebases or extreme
production ratios. Model arithmetic can revert outside its representable domain;
normal-call rules exclude such executions.

The model assumes token/dependency authorizations and allowances are already
satisfied. Share transfers are exact and non-reentrant. Burner requests consume
model shares immediately. The withdrawal model covers one request submission,
not queue limits, finalization or redemption. wstETH behavior is constrained to
this model's conversion semantics.

The exposed `credit` and `debit` functions test internal ledger transitions.
They do not require corresponding token movement. Accordingly there is no
claim that every possible harness method preserves reserve backing. Credit
addition uses explicit mathematical no-overflow preconditions, matching the
production unchecked additions. Bond debt is measured in pooled ETH units;
ledger balances are shares. Dust behavior is intentional.

Claim rules use a caller-provided claimable cap. They establish internal handling
of that cap, not that `Accounting` computes or authorizes the correct cap.

## BondLock

For a nonzero deadline expiry is inclusive: `until <= block.timestamp`;
`until == 0` is not expired. The stored amount can remain
nonzero after expiry until an explicit cleanup or replacement operation. There
is no automatic transaction at expiry.

A live lock accumulates amounts and does not shorten its deadline. A lock at
exact expiry replaces the previous amount. New lock operations increment the
nonce modulo `2^256`, as the implementation uses unchecked increment. Unlocks
do not increment it. Guarded transitions include representability/period bounds.

The harness fixes the constructor's period bounds to a minimum of 1 and a
maximum of `2^64 - 1`. Period checks cover this configuration, not the min/max
selected by a production Accounting deployment.

The harness exposes initialization for the primitive. It does not establish
production Accounting roles, delayed-penalty nonce validation, compensation or
settlement composition.

## FeeSplits

The production maximum is ten recipients. For transition rules starting from an
existing configuration, the spec explicitly constrains its length to this
validated domain. No arbitrary corrupt-storage configuration is assumed safe.

Duplicate recipients, the harness itself as recipient and an empty split list
are permitted. The forbidden token-recipient check is separate. Per-recipient
floor rounding can leave dust with the operator. Pending shares include the
operator's retained remainder, so they are not equal to the sum of outgoing
transfers. Arithmetic totality rules bound multiplication as documented in CVL.

This suite covers computation and pending bookkeeping, not actual payment,
Accounting claim ordering or penalties between reward credit and settlement.

## FeeDistributor

The token model preserves exact shares, handles sender/recipient aliases and
does not perform callbacks. The real production Merkle verification code is
used with a proof of exactly one sibling. Helpers only compute compatible roots
or expose state; they do not override production proof validation.

Oracle reports constrain current, incoming and overwritten-history strings to
bounded lengths (at most 64 bytes where specified) or require a fresh history
slot. Those premises must be checked individually. They are a tractability
boundary, not an invariant established by this suite. All-depth Merkle and
arbitrary-length string behavior remains unproved.

The production implementation disables initializers in its constructor;
executable tests initialize a proxy. CVL transition rules use arbitrary storage
with explicit caller/role/ledger preconditions and do not establish an
initialized-state invariant. Access checks cover the actual production
entrypoints, while correct assignment of roles and production addresses remains
a deployment validation task. The oracle is permitted to choose content; no property proves
the fairness or truth of a rewards tree. Contract self-aliases are handled where
exact token balance deltas are asserted.

## DepositAllocator

Allocation checks instantiate exactly two operators, positive normalized X96
shares and bounded scalar input types. The bounds ensure arithmetic and packed
imbalance representability. This does not establish arbitrary-length allocation
correctness, desired fairness, full budget utilization or MetaRegistry accuracy.

Standalone quantization rules cover their stated scalar domain. Packing rules
use the actual 224-bit imbalance and 32-bit index representable ranges. Small
heap checks include two and three keys to exercise ordering, permutation and
tie-break behavior; they are not an induction proof over arbitrary heap sizes.

## Result review checklist

Before attaching a proof claim to a release, preserve the exact source/tool
versions and answer:

1. Which properties have successful Prover and sanity results?
2. Which inputs, initial states, methods and loop depths were excluded?
3. Did every relevant external call resolve to the intended code/model?
4. Were assembly/storage and memory analysis warnings resolved?
5. Which seeded CVL mutants were detected, survived or inconclusive?
6. How were the initialization and upgrade base cases established?
7. Which dependency, oracle, governance and liveness assumptions remain trusted?
