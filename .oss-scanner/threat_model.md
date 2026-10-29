# Lido staking modules threat model

The goal is to protect operator bonds and rewards, allocate Lido stake to eligible validator keys, and account for withdrawals and penalties once. A defect in this repository can harm an individual operator or the wider stETH pool. The shared framework serves two active mainnet modules with different admission and allocation rules.

## 1. Scope and deployment context

The scan target is `lidofinance/staking-modules#main`. This model was prepared on 2026-10-13 against `e192948145afb3c8f2c35f151309144e9d58fb87`. The active mainnet code corresponds to release `v3.0` (`4d3de6658499e1c1774951780a97d7ae25ca18b8`). CSM v3 and Curated Module v2 were activated on 2026-07-24. Their deployment artifacts record distinct source commits: `4d3de6658499e1c1774951780a97d7ae25ca18b8` for the CSM upgrade and `3b0c016c77590c208f2b71ca51410cb55ea2dcc2` for Curated Module v2. The `src/` trees at those two commits are identical. The only `src/` difference between that release and the reviewed `main` is `interfaces/IStakingRouter.sol`. That comparison establishes source correspondence, not current deployed bytecode parity. `git diff e192948145afb3c8f2c35f151309144e9d58fb87 HEAD -- src` identifies later source changes.

The primary scope is production Solidity under `/src/src/`, including shared libraries, oracle contracts, proxies and gates. A utility under `src/utils/` matters when a live contract still authorizes it or a repeatable production operation uses it. An already executed setup operation does not by itself establish a current attack path. Tests, deployment scripts, generated documentation, ICS eligibility assessment, artifact generation and testnet-only effects are supporting material outside the primary scope.

The runtime instances are separate even when they share source code:

| Configuration               | Mainnet status in the reviewed evidence                                               | Security distinction                                                                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CSM v3, module 3            | Active; module proxy `0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F`                     | Permissionless admission through a gate; `0x01` validators; priority deposit queues; top-ups and balance reports disabled by the existing deployment's upgrade path. |
| Curated Module v2, module 4 | Active; module proxy `0xDa5F930cE326EB5205085D66c72A4E79d60cB8C1`                     | Allowlisted admission, operator groups and weighted stake allocation; `0x02` validators, top-ups and incoming consolidations.                                        |
| Separate CSM `0x02` stack   | Listed as proposed in the 2026-10-12 registry snapshot; not an activation of module 3 | A separate scratch initialization enables CSM's top-up queue. This configuration must not be assumed reachable through the active module-3 proxy.                    |

The [mainnet registry](https://docs.lido.fi/deployed-contracts/) distinguishes the separate proposed CSM `0x02` deployment from the active modules. The reviewed `main` checkout predates that deployment's artifacts. Proposed mainnet or active testnet wiring does not establish a reachable active-mainnet path. Shared code used by an active module remains in scope. A configuration-dependent finding needs the affected instance, prerequisite and deployment status.

`artifacts/mainnet/csm/upgrade-v3-mainnet.json` and `artifacts/mainnet/curated/deploy-mainnet.json` record addresses, constructor inputs and deployment-time parameters. Each module has its own bond pool, Accounting, parameters, fee oracle/consensus, fee distributor, verifier, strikes, ejector and gates. These artifacts and the registry are snapshots. They do not prove current role holders, parameter values or registrations.

The Dockerfile fetches optional, commit-pinned references outside the scan target:

- `/opt/lido/core`: production release `v4.1.0`, for calls into stETH, wstETH, Burner, WithdrawalQueue, StakingRouter and TriggerableWithdrawalsGateway.
- `/opt/lido/lido-improvement-proposals/LIPS/`: design intent, especially LIP-27 (Pectra compatibility), LIP-29 (CSM v2), LIP-30 (triggerable withdrawals), LIP-33 (CSM v3 and Curated Module v2), and LIP-35 (Staking Router v3: balance accounting, top-ups and consolidations).
- `/opt/lido/deployed-contracts.md`: registry snapshot from 2026-10-12. Reference commits are in the Dockerfile and fetched Git metadata.

A missing reference means its optional fetch failed. Lido core, lido-oracle, the prover service, Easy Track, Circuit Breaker, Dual Governance, EDF and other staking-module implementations are external projects. Their behavior can establish the consequence of a staking-modules defect. A defect confined to an external project belongs to that project's scan. Easy Track and Circuit Breaker enter this model through their configured role authority; their source repositories are not included in the image.

## 2. Assets and important components

The assets are operator bond shares, funded but undistributed reward shares, payout authority, signing keys, deposit and top-up allocations, reported validator balances, and the ability to request exits and reclaim excess bond. Validator principal belongs to the Lido pool and withdraws to Lido's withdrawal vault. The modules hold operator collateral and rewards rather than validator principal.

All paths below are relative to `/src/`:

- **Shared operator lifecycle:** `src/abstract/BaseModule.sol`, `src/lib/NodeOperatorOps.sol`, `src/lib/NOAddresses.sol`, `src/lib/SigningKeys.sol`, and `src/abstract/ModuleLinearStorage.sol`. These control operator identity, keys, counters, targets, permissions and router callbacks.
- **Bonds, rewards and penalties:** `src/Accounting.sol`, `src/abstract/{BondCore,BondCurve,BondLock,FeeSplits}.sol`, `src/FeeDistributor.sol`, `src/lib/GeneralPenaltyLib.sol` and `src/lib/WithdrawnValidatorLib.sol`. Share conversions, debt recovery, claims, lock settlement and operator isolation are central.
- **Deposits and stake allocation:** `src/CSModule.sol`, `src/CuratedModule.sol`, `src/MetaRegistry.sol`, `src/ParametersRegistry.sol`, queue libraries, `src/lib/StakeTracker.sol` and `src/lib/allocator/`. Initial deposits, top-ups and external Curated v1 stake use distinct accounting inputs.
- **Proofs and exits:** `src/Verifier.sol`, `src/ValidatorStrikes.sol`, `src/Ejector.sol`, `src/ExitPenalties.sol`, `src/lib/{SSZ,GIndex,Types,KeyPointerLib}.sol`. An accepted proof can burn bond, mark a key withdrawn or change allocation state.
- **Reports, admission and authority:** `src/FeeOracle.sol`, `src/lib/base-oracle/`, `src/PermissionlessGate.sol`, `src/VettedGate.sol`, `src/CuratedGate.sol`, `src/abstract/MerkleGate.sol`, factories, pause helpers, asset recovery and `src/lib/proxy/OssifiableProxy.sol`.

Vendored dependencies matter where a defect reaches these contracts. A known upstream issue without a reachable project consequence is not a new staking-modules finding.

## 3. Actors and trust boundaries

### Adversarial users and operators

Any address can submit permissionless proofs, reward proofs, queue-cleaning calls and allowed maintenance transactions. An attacker can operate several node operators, control manager and reward addresses, deploy recipient contracts, arrange transaction ordering and shape valid consensus-layer activity through validators the attacker controls. A node operator is not trusted to report its own performance, preserve its queue position fairly or submit a balance proof that increases its eventual penalty.

Operator authority is local to an operator. Manager and reward addresses have different rights, and extended manager permissions intentionally change those rights. A custom rewards claimer may trigger a claim but does not select a replacement reward recipient. Caller-supplied `from`, operator ids, key indices, pubkeys, permits, Merkle leaves, fee-split recipients and refund recipients are untrusted inputs.

Permissionless CSM admission means that anyone can use `PermissionlessGate`. `BaseModule.createNodeOperator` itself requires `CREATE_NODE_OPERATOR_ROLE`. Vetted and curated gates bind a Merkle eligibility proof to an address and consume that eligibility once. Curated gates intentionally create an operator without requiring keys or bond in the creation call and assign extended manager permissions. Eligibility does not authorize changing another operator's payout or keys.

The modules use optimistic key vetting. `SigningKeys` checks input shape and stores keys/signatures, but does not verify BLS deposit signatures on-chain. `NodeOperatorOps.addKeys` extends the vetted pointer only when all previously added keys are still vetted. Removing non-deposited keys resets the pointer to the remaining key count, so an invalid tail may need unvetting again. Core DSM guardians inspect deposit data off-chain for invalid signatures and deposit front-running, and DSM can reduce the module's vetted pointer through StakingRouter. Module nonces bind DSM deposit authorization to the current deposit state. The on-chain vetted count alone is not proof that those off-chain checks ran.

### Privileged actors with explicit bounds

- **StakingRouter:** the configured router has `STAKING_ROUTER_ROLE` and supplies deposit requests, top-up inputs, target limits and exit-related callbacks. It also forwards rewards through `onRewardsMinted` and can reduce the vetted-key pointer through `decreaseVettedSigningKeysCount`. The module trusts the router's key association and input conventions, including unique top-up entries. An ordinary operator cannot impersonate the router. A defect in how this repository constructs or consumes an otherwise valid router interaction remains in scope.
- **Proof verifier:** `reportValidatorSlashing` and `reportValidatorBalance` require `VERIFIER_ROLE`. Ordinary withdrawal settlement instead requires `REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE`, used by the Verifier through `reportRegularWithdrawnValidators`. Its public proof entry points are adversarial surfaces. Acceptance of a fabricated root, wrong key or wrong withdrawal, or a replay that repeats settlement or penalty effects, is a verifier defect rather than intended privileged authority. Repeating a valid withdrawal proof after settlement may succeed without another accounting effect.
- **FeeOracle and HashConsensus:** each module has a separate oracle and quorum. Honest quorum agreement is assumed for real-world performance and reward data. A single member can vote, and a member or `SUBMIT_DATA_ROLE` holder can submit agreed data subject to hash, version, frame and deadline checks. One participant cannot choose a new accepted report without consensus. Contracts enforce report consistency and funding, not the truth of beacon duties collected off-chain.
- **Penalty roles:** a holder of `REPORT_GENERAL_DELAYED_PENALTY_ROLE` can report and cancel a bond lock using a caller-selected penalty type and amount. A holder of `SETTLE_GENERAL_DELAYED_PENALTY_ROLE` can settle the lock subject to its nonce and expiry. A holder of `REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE` supplies slashed-withdrawal penalty amounts. These powers are intentionally broad; the bond amount is not a universal cap on debt. Unauthorized entry, wrong-operator effects and violations of the lock or withdrawal state machine remain in scope.
- **Operator-address admin:** if granted, `OPERATOR_ADDRESSES_ADMIN_ROLE` permits replacement of both manager and reward addresses through `changeNodeOperatorAddresses`, without the operator confirmation flow. This describes the role capability, not evidence of a current holder.
- **Gates and parameter/group managers:** role holders can set eligibility roots, bond curves, operational parameters and curated groups within each setter's checks. A Merkle-root replacement can revoke unused eligibility. It cannot remove an operator already created under an earlier root. Group membership and internal shares control curated allocation; a bond-curve id also selects parameter overrides and curated type weight.
- **Pause and recovery roles:** pausers may stop the entry points that check `whenResumed`, including an indefinite authorized pause. Recovery authority covers stray assets within the specific recovery method's restrictions. Accounting's collateral and FeeDistributor's funded rewards are not stray stETH. A pause is not a blanket restriction on every function in the contract.

The recorded mainnet model gives the CSM and Curated Module committees direct general-penalty reporting/cancellation authority. Easy Track routes settlement, slashed-withdrawal reports, gate-tree updates and curated-group changes through governance motions. The registry records the committees and factories, while the source enforces the target contract's role and structural checks. A current holder or motion delay needs deployment or on-chain evidence; it cannot be inferred from an interface alone.

### Trusted systems and governance

Assume Ethereum consensus, EIP-4788 roots and the configured consensus SSZ schema are correct. Core stETH/wstETH, Burner, WithdrawalQueue, locator, router and withdrawal gateway are trusted to honor their interfaces. Invalid roots fabricated through a test cheatcode do not establish a real attack.

The DAO's Aragon Agent controls proxy/admin authority in the recorded deployment. Governance may upgrade logic, grant roles and choose values that setters accept. Authorized confiscation through penalty roles or replacement logic is not prevented by a universal no-seizure invariant. Governance capture, leaked privileged keys and conduct that stays within intended authority are excluded. A contract invariant that fails under an accepted configuration can still be relevant, with the setter, value and required authority stated.

## 4. Security properties

These properties are subject to the intended behavior and public limitations in section 6. Prior audits do not establish that every reachable implementation path satisfies them.

### Operator collateral and rewards

- Accounting's stETH shares cover `totalBondShares()`. An operator's bond ledger and the aggregate ledger change together. Claims, wrapping, burns and recovery cannot consume another operator's shares or funded collateral. ETH bond deposits submit ETH to Lido and credit the shares actually received; stETH and wstETH deposits use their share conversions.
- Required bond follows the assigned curve for non-withdrawn keys, plus locked bond and bond debt. Top-ups do not increase the key-count curve requirement. Claimable bond shares are clamped to the positive difference between current and required bond shares. Wrapping and withdrawal requests debit the shares actually spent. New bond or reward shares repay debt before increasing free bond.
- Burning above the available bond records the uncovered amount as `bondDebt`. Charging a fee transfers available shares without creating that debt. These two paths have different economic consequences.
- Reward proofs bind the operator and cumulative reward shares to the accepted root. Already distributed shares cannot be claimed again, and total distribution stays within shares actually funded. Oracle root replacement cannot reset an operator's distributed counter.
- Payouts follow the authorized reward address and fee splits. Fee splits have at most ten recipients and total at most 10000 basis points. When splits already exist, changing or removing them requires a valid rewards proof with zero distributable shares. An invalid or empty proof also reverts. Installing the first split skips only that proof check. Every split update, including installation and removal, also requires zero `pendingSharesToSplit`. Pending split shares and required bond must remain consistent across deposits, debt recovery, claims and penalties.

### Locks, withdrawals and penalties

- A delayed penalty report locks the identified operator's bond. Settlement uses the current lock nonce, handles expiry and cannot burn the same lock twice. Cancellation, compensation and expiry cannot leave a stale settlement authorization valid for a later lock.
- Compensation burns the operator's existing excess bond. It does not accept fresh ETH in the compensation call and cannot take another operator's collateral. Settlement and compensation timing follow the lock state rather than a guaranteed operator grace period.
- A withdrawal or slashing report binds the deposited operator key to the proved validator. Withdrawal accounting occurs once, reduces the non-withdrawn key count once and applies the appropriate shortfall, slashing or exit penalty once. Slashing marking and withdrawal settlement are distinct stages.
- Size-scaled exit penalties use the intended validator balance and parameters. `ExitPenalties` skips voluntary-exit fee reports and records `min(paidFee, configuredMaxFee)` for other exit types. It keeps the first recorded request fee and strikes penalty. The delay fee requires a duration above the configured allowed exit delay and is recorded once. The `(operatorId, pubkey)` used when recording an exit penalty must correspond to the `(operatorId, keyIndex)` later consumed under the trusted router association.

### Deposit allocation and module accounting

- Keys returned for deposits are registered, within the optimistic vetted-key pointer, non-deposited and eligible under bond, target and parameter constraints. That pointer does not establish cryptographic key/signature validity. Key removal cannot remove an already deposited validator. Counts and key ranges remain consistent after partial batches, withdrawals and authorized unsafe updates.
- Changes to registered deposit data or cached ready-to-deposit key eligibility invalidate earlier DSM attestations by changing the module nonce. Consuming deposit data also changes the nonce. A configuration change that requires a full refresh changes the nonce before the refresh and blocks initial deposits and Curated Module v2 top-ups until the refresh completes. No-op refreshes and cleanup of batches that cannot contribute deposit keys need not change the nonce. A different allocation among already eligible keys is not by itself evidence of a stale attestation admitting an unchecked key. Public maintenance must not permit repeated nonce invalidation without a relevant deposit-state change to deny deposits.
- CSM priority queues cannot create a second deposit of a key or grow beyond backed eligibility through repeated enqueue, cleaning or removal. A temporarily ineligible position may be removed as described in section 6.
- Curated initial deposits respect cached depositable counts, bond eligibility, target limits and allocation weights. Top-up allocations stay within the weighted allocation, available validator headroom, per-key limits and quantization. An operator with zero MetaRegistry weight has zero depositable keys. An operator's group and external stake cannot be counted multiple times through duplicate membership or external-operator references.
- Allocated balance, confirmed balance, operator extra stake and total module stake remain consistent across deposits, top-ups, incoming consolidations and withdrawals. A balance proof may raise confirmed balance without a local top-up; incoming stake is a real consensus-layer event.
- A curve or weight edit invalidates cached deposit information. Initial deposits and Curated Module v2 top-ups remain blocked until `batchDepositInfoUpdate(maxCount)` has completed the required operator sweep. Per-operator changes refresh the affected operator. A refresh or queue operation cannot authorize an unrelated user's configuration change.

### Proofs, reports and exits

- Public proof calls derive a root from EIP-4788 and bind the header/state, validator, registered pubkey and applicable slot conditions. Withdrawal proofs additionally check the validator credential destination and the withdrawal recipient. Balance and slashed proofs do not independently check withdrawal credentials. SSZ field encoding, gindex bounds/concatenation, historical-summary selection, fork pivots and gwei-to-wei conversion are part of the proof boundary.
- Withdrawal qualification uses the configured `MIN_WITHDRAWAL_RATIO` against `32 ETH + keyConfirmedBalance`. Validator identity and full-versus-partial withdrawal semantics must both hold. An authentic consensus proof does not by itself establish that the proved event is the event the module should settle.
- Reports match the agreed hash and allowed consensus version, arrive in the processing window and advance the expected ref slot. A report cannot reuse consumed rewards or bypass a missing consensus through a secondary submission path.
- A strike proof binds the operator/key and strike data to the accepted strikes root. The ejection path checks the configured threshold. `ExitPenalties` records a strikes penalty only once for a key, while a valid strike proof can trigger further exit requests before withdrawal. Reward proofs and strike multiproofs have different leaf schemas and empty-proof behavior.
- Voluntary ejection requires operator-owner authority; strike-driven ejection requires the configured Strikes contract. Keys are deposited and not already withdrawn. Voluntary batches reject duplicate key indices. The strikes path has no independent batch-deduplication or proof-replay guard, but every submitted multiproof must still validate against the accepted root. ETH fees/refunds follow the gateway interface. Cached staking-module identity cannot direct a request to another instance.
- Role, pause, initialization and proxy checks hold across external calls. A successful call cannot leave the module, Accounting or a queue in a state that admits deposits against stale eligibility.

## 5. Integration details that affect impact

CSM's bond is the first source of penalty coverage, not a full guarantee against every validator loss. Curated Module v2 uses a much smaller operational bond and relies on curation, target limits and exit mechanisms for residual protection. A burn that exhausts a curated operator's bond can create debt, make every non-withdrawn key unbonded and force its target toward zero. The origin and authority of that burn determine whether this is intended operation or an attack.

Curated top-up eligibility is separate from initial-deposit eligibility. In the reviewed code, the operator baseline checks non-zero effective weight and quantized capacity, but does not check bond coverage or the stored or derived target limit. An operator whose bond shortfall produces a forced target of zero can therefore remain eligible for top-ups if the other allocation and per-key checks pass. Eligibility does not guarantee a non-zero allocation. The intended top-up policy during this exit-targeting state remains unconfirmed and is open to assessment, rather than an accepted-risk exclusion. TopUpGateway sets a key's limit to zero if its supplied authentic consensus proof shows slashing or an `exitEpoch` other than `FAR_FUTURE_EPOCH`; a module-side target or exit request does not by itself establish that state.

`MetaRegistry` includes legacy Curated v1 stake in curated allocation targets, valuing each legacy active validator at 32 ETH. It apportions a group's external stake to an operator by effective weight before the initial-deposit allocator divides that apportioned amount by 2048 ETH and rounds down. Internal active keys count as whole validator units. Top-ups instead distribute ETH toward weighted targets. Count fairness and ETH fairness are different properties.

In Curated Module v2 and a separately initialized CSM `0x02`, permissionless balance proofs raise confirmed extra balance and preserve previous highs in `StakeTracker`. Historical proofs can establish a past high before the validator became withdrawable, so a submitter can raise the exit-shortfall base even when the current balance is lower. External deposits and incoming consolidations can raise that tracked balance. Withdrawal settlement removes it. Prover freshness affects both allocation and exit-shortfall assessment. Active CSM module 3 rejects balance reports because its top-up queue is disabled. Its balance-proof high-water path is unavailable and its withdrawal expected balance remains 32 ETH; base per-key stake and withdrawal tracking still apply.

The withdrawal-proof path checks the low 20 bytes of validator withdrawal credentials against `WITHDRAWAL_ADDRESS`. That intentionally accepts either credential prefix with the same destination. The configured module and proof entry point impose the remaining applicability restrictions. A credential proof alone does not identify which module owns the key.

The normal withdrawal-proof path rejects slashed validators; slashed withdrawals use a separate role-mediated reporting route. The verifier's constructor parameters include previous/current gindices and fork slots. A change to consensus container shape or the slot clock may need replacement contracts; changing oracle frame length does not change immutable seconds-per-slot or genesis time.

Node operators, proof submitters and fee-split recipients can be contracts. Claims and permits call the trusted token or withdrawal queue, fee splits transfer stETH shares, and Ejector calls the gateway with a caller-selected refund recipient. Relevant reentrancy needs the actual callback path and state transition rather than a hypothetical arbitrary token substituted for a configured dependency.

Core views and module views also feed honest off-chain services. A view defect is rated by the harmful allocation, claim, report or transaction constructed from it and by later on-chain checks. A malformed view result with no reachable consequence is not equivalent to asset loss.

## 6. Intended behavior and public accepted limitations

The following mechanisms help distinguish a new defect from a known design cost. A variant with a new bypass, different trust requirement, lower attacker cost or greater impact remains relevant.

- **Broad privileged penalty powers:** reporting can lock an arbitrary amount, and settlement or slashed-withdrawal reporting can burn available bond and create debt. Code separates role authority and lock state; it does not independently judge committee evidence or cap every penalty at a posted bond.
- **Deposit-info maintenance:** curve/weight changes intentionally block deposits until the full refresh completes. Permissionless queue cleaning can remove positions that became ineligible during a lock or bond shortage. Some public refresh calls safely do nothing for an unknown operator. These facts do not authorize bypassing freshness or depositing an underbonded key.
- **Cached eligibility and negative rebases:** a negative stETH rebase can reduce cover before cached CSM depositability is refreshed. The framework exposes refresh paths; a larger or repeated loss path needs separate analysis from the existence of this cache interval.
- **Bond and payout semantics:** tiny share-conversion dust is expected. Pending fee-split shares remain part of the bond ledger until settled, including in key-cover calculations. Some claimable-value views do not subtract pending splits. Extended manager mode intentionally allows a one-step reward-address change. A nominated claimer still pays the configured recipient. An unstETH NFT sent to a passive contract requires that contract to redeem it.
- **Full-withdrawal heuristic:** the withdrawal-ratio check cannot independently prove that a record is the full withdrawal. A sufficiently large partial or later sweep can qualify. LIP-29 records the older rare edge, and LIP-33 describes its changed ratio-based mitigation plus the top-up-during-exit case for `0x02` validators, reachable in active Curated Module v2 and applicable to a separately enabled CSM `0x02` configuration. These mechanisms depend on the authentic consensus event, qualification threshold and proof ordering. The top-up-during-exit case does not apply to active CSM module 3.
- **Public CSM v3 / CM v2 audit limitations:** Certora's June 2026 report records L-01 (the consolidation interval before a balance proof), L-02 (initial count-based allocation bias), L-03 (a top-up during exit can produce two valid withdrawal records), and L-05 (confirmed-balance freshness depends on an honest prover). I-03/I-04 cover passive-contract unstETH redemption and one-step extended-mode reward-address changes. These are specific mechanisms, not exemptions for arbitrary accounting or proof errors.
- **Top-up distribution:** Statemind's June 2026 INFORMATIONAL-17 records reduced distribution when baseline weight includes operators whose per-key top-up limit prevents allocation. Quantization removes sub-step capacity, while that per-key limit can still leave a remainder. INFORMATIONAL-14 records the reliance on correct router pubkey association for exit-penalty lookup.
- **Exits and oracle availability:** gateway rate limits, request fees and consensus-layer congestion can delay exits. A repeated valid exit request is not automatically a second withdrawal or penalty. Consensus members can create report variants, and the public HashConsensus gas-limit concern is tracked as [issue #565](https://github.com/lidofinance/staking-modules/issues/565). A quorum failure or authorized pause alone is not an unprivileged liveness defect.

The public audit reports are [Certora CSM v3 / CM v2](https://github.com/lidofinance/audits/blob/main/Certora%20Lido%20CSM%20v3%20and%20CM%20v2%20Audit%20Report%20-%2006-2026.pdf) and [Statemind CSM v3 / CM v2](https://github.com/lidofinance/audits/blob/main/Statemind%20Lido%20CSM%20v3%20and%20CM%20v2%20Audit%20Report%2006-2026.pdf). Their summaries above are available without a network; the PDFs are not bundled in the image. Retired CSM v1/v2 queue migration and referral behavior should not be treated as current code solely because an older audit describes it.

## 7. Severity guidance

Rate the worst demonstrated consequence the same root cause can reach. State the deployment, configuration, attacker authority and required parameter values.

- **Critical:** theft or permanent freezing of validator principal or operator bond collateral, or an accounting failure that leaves stETH obligations without sufficient backing.
- **High:** theft or permanent freezing of unclaimed operator rewards, unauthorized operator or administrative takeover, bypassed DSM authorization, unauthorized forced exits, or temporary freezing of funds. A bypass that causes principal theft or insufficient backing reaches Critical.
- **Medium:** unprofitable griefing, harmful front-running with bounded impact, harmful allocation or exit delays without frozen funds, a new or cheaper deposit/top-up halt, or a report failure that recovers without governance action.
- **Low:** promised returns not delivered without loss of value, or incorrect views/events without a harmful effect on funds or protocol decisions.
- **Informational:** style, gas, best practices, unreachable code, or negligible rounding that cannot accumulate. Do not submit these as findings.

A freeze is permanent for this guidance if no non-upgrade role or user action supported by the existing deployed code can restore access to the funds, even if an upgrade or redeploy could. State any recovery action, its authority and its delay. A halt in deposits or top-ups alone does not establish that user funds are frozen.

Intentional self-harm is Informational only if every resulting loss stays with the actor. Loss shifted to stETH holders or other operators is not self-harm. An unintended loss suffered by an honest user during ordinary use is not intentional self-harm. Rate views and off-chain effects by their demonstrated downstream consequence.

Quantify the total reachable loss in ETH and shares, including repeated use and affected operators. State the duration and attacker cost for a freeze or delay. A freeze that requires many costly transactions to maintain can be Medium griefing. Severity, confidence and reproduction status are separate.

An actor intentionally exercising a privileged power is not a vulnerability solely because the result is harmful. An ordinary user reaching that power, a role holder exceeding its code-enforced authority, or one operator harming another through a supposed local action can be a finding. A live configuration that disables an attack path limits current severity; the same source under a proposed configuration needs a separate reachability statement.

## 8. Build and offline tests

The image installs the repository's Yarn dependencies and Foundry version from `.foundryref`, then compiles sources, scripts and tests while network access is available. The reviewed version uses Foundry `v1.5.1`, Solidity `0.8.33`, the Osaka EVM and optimizer runs `150`. Node follows the repository's major version 20, and Yarn is `4.1.1`. The final image retains `node_modules`, compiler binaries, artifacts and caches.

The unit-test command from `Justfile`, with offline compiler resolution, is:

```sh
cd /src
env -u FOUNDRY_THREADS forge test --offline --skip script --no-match-path 'test/fork/**' -vvv
```

A focused reproducer can run with:

```sh
forge test --offline --skip script --match-path 'test/unit/Accounting/*.t.sol' -vvv
forge test --offline --skip script --match-path 'test/unit/Verifier*.t.sol' -vvv
```

Verifier fixtures use `vm.ffi` to run local Node scripts. `foundry.toml` enables FFI and permits the required fixture/artifact paths. These scripts and their npm packages must be present even though the tests have no RPC dependency. `test/helpers/`, including `test/helpers/mocks/`, provides local support for reproductions. The Dockerfile runs a bounded Verifier smoke test and reports its failure without hiding a dependency or compilation failure.

`test/fork/` deployment and integration suites require RPC access and deployment/environment configuration. They cannot run against a fresh live fork in the scanner's disconnected environment. Passing units does not establish current mainnet role wiring, bytecode parity, core integration, oracle performance truth or consensus-layer settlement. Existing mocks are suitable for local state-machine reproduction, but a mocked root or privileged caller must correspond to an achievable production prerequisite.

## 9. Useful reports and patch constraints

A useful report identifies the affected contract/function, attacker authority, operator/module configuration, state prerequisite, transaction sequence and observable loss or disruption. A local Foundry reproducer can show the state transition. Required role grants, changed constructor values, fabricated consensus roots and mocked external behavior need to be explicit so that deployment reachability can be assessed.

Authorized pauses and recovery are mitigations only for the entry points and assets they actually cover. Source and static registry data do not establish current role holders, operator response time, committee availability or whether a pause lands before the attack. Recovery that needs a DAO vote is different from permissionless recovery.

Patches must preserve deployed storage. `ModuleLinearStorage` deliberately starts its struct at slot 0 to retain legacy CSM layout. Each component's existing linear layout, storage namespace or unstructured slot must be preserved. Initializers and version finalizers depend on the intended atomic deploy/upgrade sequence. Proxy upgrades, replacement of non-proxy contracts (including Verifier, Ejector, HashConsensus and PermissionlessGate), immutable dependencies and linked libraries require different rollout actions. A Solidity-only fix that changes a constructor input, library address or authority may require deployment and role migration beyond this repository's code change.
