# Staking modules verification

This directory contains Certora specifications over production implementations,
thin Solidity harnesses, executable dependency models, and RPC-free Foundry
witnesses. It is an initial verification workstream, not a claim that the staking
modules have been formally verified.

The implementation starts from `develop` commit
`7bdcfb631b13d24e8fae3b5ba0e11d4be07b84f9`. No production Solidity behavior is
changed. The scope is five reusable primitives; full `Accounting` integration,
deposit queues, oracle correctness, upgrade safety and the `Verifier` remain
future work. In particular, this work does **not** yet establish that a public
`Accounting.claimRewards*` call preserves the required bond.

## Three different kinds of evidence

| Check                         | What it establishes                                                            | What it does not establish                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `run.py check`                | Solidity compilation and CVL parsing/typechecking with the pinned CLI/compiler | Satisfaction of properties, absence of vacuity, adequate loop unwinding, resolved backend analysis |
| Foundry tests and `mutate.py` | Executable witnesses and sensitivity to specified production defects           | Exhaustive symbolic coverage or strength of the CVL specifications                                 |
| `run.py prove`                | Sends jobs and waits for the cloud Prover's rule results                       | Guarantees outside the documented scene, bounds, preconditions and cryptographic assumptions       |

Local compilation is recorded as `compiled_not_proved`. A successful cloud CLI
invocation is recorded as `prover_completed_review_rules`; review the per-rule
report, sanity results, call resolution and analysis warnings before declaring a
property proved. Backend timeouts and analysis failures are unresolved work.

## Scope

The machine-readable inventory is [`suites.json`](suites.json). The rules live in
[`specs/`](specs/); their comments and preconditions are part of the specification.
See [`ASSUMPTIONS.md`](ASSUMPTIONS.md) before interpreting any result.
The initial executed checks and remaining proof gates are recorded in
[`STATUS.md`](STATUS.md).

| Suite            | Intended properties                                                                                                               | Boundary                                                                                                                                 |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| BondCore         | Individual/global ledger deltas, debt behavior, caps on burn/charge/claims, observed share movement, nonzero witnesses            | Actual inherited internal methods; fixed-rate non-reentrant dependency models; no public Accounting authorization or required-bond check |
| BondLock         | Active accumulation versus expired replacement, inclusive expiry, unlock semantics, period bounds, operator isolation, nonce wrap | Internal lock primitive; no permission checks or delayed-penalty settlement composition                                                  |
| FeeSplits        | Configuration guards, basis-point arithmetic, retained remainder, pending bookkeeping, operator isolation                         | Validated split length up to 10; no actual token transfers or Accounting composition                                                     |
| FeeDistributor   | Cumulative delta/idempotence, funding obligations, access control, history and recovery restrictions                              | Production methods with exact-share model, actual one-sibling Merkle proofs, bounded strings and explicit transition preconditions       |
| DepositAllocator | Allocation conservation, capacity/request bounds, step quantization, zero input, packing and small heap behavior                  | Allocation with exactly two operators and bounded numeric inputs; separate two/three-key heap checks; no global fairness claim           |

The suites contain both safety assertions and positive `satisfy` witnesses.
Witnesses establish satisfiability within the specified scene when checked by
the Prover. They do not establish reachability from a deployed proxy or liveness.

## Install

Use the repository's Node version (`.nvmrc`), pinned Foundry (`.foundryref`),
Java 21+, Python 3.12 and native Solidity 0.8.33. Solidity configuration matches
`foundry.toml`: Osaka, optimization enabled, 150 runs, no via-IR.

```sh
node .yarn/releases/yarn-4.1.1.cjs install --immutable
python3 -m venv certora/.venv
. certora/.venv/bin/activate
python -m pip install -r certora/requirements.txt
solc --version
forge --version
certoraRun --version
```

Install native `solc` 0.8.33 from the official Solidity release and make it
available as `solc` on `PATH`. The CI workflow downloads that exact binary and
checks SHA-256 `1274e5c4621ae478090c5a1f48466fd3c5f658ed9e14b15a0b213dc806215468`.
The CLI is pinned in `requirements.txt`; a passing local typecheck does not
establish that the cloud backend supports every Osaka instruction or storage
analysis pattern.

## Local validation, without credentials

Run from the repository root:

```sh
python certora/run.py list
python -m unittest discover -s certora/tests -v
python certora/run.py check
FOUNDRY_PROFILE=formal forge test --use "$(command -v solc)" -vv
python certora/mutate.py --solc "$(command -v solc)"
```

Select suites with repeatable `--suite`, for example:

```sh
python certora/run.py check --suite BondLock --suite FeeSplits
python certora/mutate.py --list
python certora/mutate.py --suite BondCore --solc "$(command -v solc)"
```

Equivalent Just recipes are `certora-check`, `test-formal`, `certora-mutate`
and `certora-prove`. The isolated `formal` Foundry profile discovers only
`test/unit/formal/` and uses 1,000 fuzz runs. These tests also remain discoverable
by the repository's usual unit-test command.

`certora/results/` and `.certora_internal/` are ignored. The main runner writes a
JSON report and per-suite logs. The source fingerprint covers production,
harnesses, models, CVL, configs and build inputs; keep it with the Prover results.

## Cloud verification

Configure `CERTORAKEY` through your local secret manager or repository Actions
secrets, never in a committed file or chat. Then:

```sh
python certora/run.py prove --suite BondLock
python certora/run.py prove
```

Without a key the command exits nonzero and submits nothing. Cloud runs consume
your Certora quota/credits; the runner does not create an account, purchase
credits or change billing. Classic Prover access and AutoProver are distinct
workflows; this repository uses `certoraRun`, not AutoProver-generated output.

The workflow [`certora.yml`](../.github/workflows/certora.yml) runs local preparation
on relevant pull requests. Cloud execution is an explicit `workflow_dispatch`
with `mode=prove`, after preparation succeeds. PRs, including fork PRs, never
receive the key or submit billable verification jobs automatically.

The runner rejects optimistic settings, rule/method exclusions and suppressed
result comparison in suite configs. It waits for cloud results. Review warnings
and assumptions even when the CLI exits successfully. A normal contract call
inside a CVL rule filters reverting paths; separate `@withrevert` totality rules
and positive examples are included where appropriate.

A timeout or cancellation stops the local client process group; it does not
cancel a job already submitted to Certora. Inspect the Prover dashboard before
retrying to avoid duplicate jobs. Cloud workflow runs are not automatically
cancelled when another preparation run starts.

## Mutation checks

[`mutations.json`](mutations.json) records manually selected defects and exact
Foundry tests expected to detect them. [`mutate.py`](mutate.py):

1. Requires the replacement text to occur exactly once.
2. Builds and runs the named baseline test in a disposable copy.
3. Builds and tests the mutant in another disposable copy.
4. Counts it as `killed` only for the named test's matching assertion failure.

A compile error, unexpected revert, missing test, incomplete output or timeout
is `inconclusive`, never a detected defect. Survived or inconclusive mutants make
the command fail. The original source tree is never edited. Stable fuzz seeds
and a default 64-run mutation fuzz budget keep comparisons reproducible; the
normal witness suite still uses 1,000 runs.

These checks validate the **Foundry witnesses**. To assess CVL specification
strength, run the same source mutations through the cloud Prover using
[`certoraMutate`](https://docs.certora.com/en/latest/docs/gambit/mutation-verifier.html)
after obtaining a passing original run. No offline mutation result in this
directory should be presented as a CVL mutation kill.

## Next verification gates

- Run all cloud suites, resolve each timeout/unwind/analysis issue, and inspect
  sanity and call resolution. Do not turn on optimistic flags to get green runs.
- Validate the CVL rules against seeded mutants using actual Prover results.
- Replace the fixed BondCore rate with symbolic ratio/rebase scenes and review
  dependency authorization and callback assumptions.
- Compose production Accounting claims, debt, locks and fee splits with the
  required-bond calculation; establish initialization and upgrade base cases.
- Add queue accounting and operator/global counter induction, then larger
  allocator models. Define fairness separately from allocation safety.

## Design references

- [Devcon 8: Bug-Free Solidity Coding Agents](https://archive.devcon.org/devcon8/bug-free-solidity-coding-agents/)
- [Devcon 6: Bad Proofs in Formal Verification](https://archive.devcon.org/devcon-6/bad-proofs-in-formal-verification/)
- [Certora: checking specifications](https://docs.certora.com/en/latest/docs/user-guide/checking.html)
- [Certora: loop unrolling](https://docs.certora.com/en/latest/docs/prover/approx/loops.html)
- [Certora: multicontract verification](https://docs.certora.com/en/latest/docs/user-guide/multicontract/index.html)
