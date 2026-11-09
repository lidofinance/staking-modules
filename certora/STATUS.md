# Initial verification validation

Date: 2026-11-09. Production base:
`7bdcfb631b13d24e8fae3b5ba0e11d4be07b84f9` (`develop`).

## Implemented scope

| Suite            | CVL rules | Foundry tests |
| ---------------- | --------: | ------------: |
| BondCore         |        21 |             5 |
| BondLock         |        19 |             8 |
| FeeSplits        |        17 |            15 |
| FeeDistributor   |        21 |            13 |
| DepositAllocator |        14 |             9 |
| Total            |        92 |            50 |

Eight CVL rules contain positive `satisfy` witnesses. The remaining rules assert
conditional safety, revert behavior or totality within their documented domains.
The executable suite contains 18 fuzz tests; a separate formal-profile run used
1,000 inputs per fuzz test. The mixed BondCore witness executes 32 operations
per generated scenario.

## Observed local results

| Validation                                                                  | Result                                                   |
| --------------------------------------------------------------------------- | -------------------------------------------------------- |
| Full `forge build` with native solc 0.8.33                                  | Passed; compiler warnings remain                         |
| Existing unit suite plus new witnesses, excluding `test/fork/**`            | 2,554 passed, 0 failed, 0 skipped across 278 suites      |
| Isolated formal-profile witnesses                                           | 50 passed, 0 failed, 0 skipped; fuzz runs 1,000          |
| Certora local Solidity compilation and CVL typechecking                     | All five suites passed                                   |
| Python orchestration and mutation-runner safeguards                         | 31 passed                                                |
| Seeded production defects checked by executable witnesses                   | 12 of 12 detected by assertions across the recorded runs |
| Repository `lint:check`, actionlint, Just recipe parsing, whitespace checks | Passed                                                   |
| Fork/deployment/integration tests and coverage measurement                  | Not run                                                  |
| Cloud Certora Prover jobs                                                   | Not run: no `CERTORAKEY` configured                      |

Tools: Foundry 1.5.1, Solidity `0.8.33+commit.64118f21`, certora-cli 8.20.3,
Java 21, Python 3.12, Node 20.10.0 and repository Yarn 4.1.1. Compiler settings:
Osaka, optimizer enabled with 150 runs, no via-IR. Native solc checksum is recorded
in the workflow and verification guide.

FeeDistributor local compilation warns about inability to generate auto-finders
for unused OpenZeppelin function-pointer overloads. No storage-layout warnings
remain in the selected local configurations. Backend analysis and call resolution
still require review after an actual Prover run.

## Mutation evidence

The initial full run detected ten defects and correctly classified two
FeeDistributor cases as inconclusive: their multi-call test reached a later
`NotEnoughShares` revert before an assertion. A focused single-claim ledger
witness was added and both defects were detected by immediate assertions on
rerun. A further targeted-build runner smoke test also passed.

Original and superseded reports are retained locally under the ignored
`certora/results/` directory. `mutations-final.json` selects the latest actual
result per seed and references its source report and hash. Nine selected older
records predate capture of witness/config hashes; those fields were not invented
after execution. New runner executions capture the hashes and stable fuzz budget.

These results establish sensitivity of the **Foundry witnesses** to twelve
selected defects. They do not measure CVL mutation coverage. Actual CVL mutation
verification requires a successful original Prover run and `certoraMutate` jobs.

## Proof status and next action

**No property is recorded as formally proved by this work.** Local typechecking
does not run SMT verification, establish non-vacuity, validate backend storage
analysis or discharge loop-unwind obligations.

Configure `CERTORAKEY` securely and dispatch the workflow with `mode=prove`, or
run `python certora/run.py prove --suite BondLock` locally. Start with a small
suite, inspect its complete report, then run the remaining suites. Keep all
timeouts, failed sanity checks and analysis gaps unresolved until investigated.

The limits in [ASSUMPTIONS.md](ASSUMPTIONS.md) remain part of every result:
fixed-rate/non-reentrant BondCore models, primitive-level authorization boundary,
one-sibling Merkle proofs and bounded report strings, exactly two allocation
operators, and no protocol-wide initialization or upgrade induction.

No production Solidity was modified. This work does not yet prove public
Accounting claims preserve required collateral, nor validate deployment roles
or oracle truth. Latest GitHub CI status is available on the pull request.
