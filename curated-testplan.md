The document describes what should be tested during `testnet` or `devnet` with Curated Module v2 contracts on live networks.

## Scope and constraints

- Curated Module shares `BaseModule` with CSModule but differs in deposit allocation (weight-based, not queue-based), operator management (MetaRegistry, admin address override), and StakingRouter interactions (top-ups, balance reporting).
- Use live network calls only: no impersonation, no prank/cheatcodes.
- Use real deployed addresses from the selected chain deployment artifact.
- This manual suite is action-driven: each scenario should include a real transaction and an observable effect.
- Static/immutable/default deploy configuration checks belong to deployment test suites, not here.
- State baseline for this suite is post-vote only (module stack already live/resumed).
- Many admin actions require governance or role-holder accounts; ensure proper auth context (e.g. Aragon agent, easyTrack executor, gate pause manager) before executing.

## Curated Module adaptation notes vs CSM

- No deposit queue — deposits are allocated via weight-based greedy algorithm (`CuratedDepositAllocator`).
- No `cleanDepositQueue`, no top-up queue, no `rewindTopUpQueue`.
- `CuratedGate` replaces `PermissionlessGate`/`VettedGate` — Merkle-based, sets metadata in MetaRegistry, always uses `extendedManagerPermissions = true`.
- `MetaRegistry` manages operator groups, weights, external operators (e.g. NOR), and metadata.
- `changeNodeOperatorAddresses` allows admin-forced address replacement (requires `OPERATOR_ADDRESSES_ADMIN_ROLE`).
- `allocateDeposits` (top-up path) and `updateOperatorBalances` are functional (CSModule stubs these as no-ops).
- `notifyNodeOperatorWeightChange` callback from MetaRegistry can zero-out depositable count.
- `requestFullDepositInfoUpdate` can be triggered by both Accounting and MetaRegistry.
- Key removal uses default behavior (no `keyRemovalCharge` penalty, unlike CSM).
- Operator with zero weight from MetaRegistry has `depositableValidatorsCount` forced to 0.
- Max effective balance per validator is 2048 ETH (EIP-7251, 0x02 credentials).
- External stake from NOR is normalized to validator-count equivalent via `externalStake / 2048 ETH`.

## Execution pattern for exit-related scenarios

- [ ] Trigger exit cause (target limit, voluntary trigger, strikes, or delay flow).
- [ ] Report exited keys in module from Staking Router (`reportStakingModuleExitedValidatorsCountByNodeOperator`).
- [ ] Wait for CSM tool to submit withdrawal report through `Verifier` (external step).
- [ ] After verifier tx finalization, check module/accounting/exit-penalties outcomes.

## CuratedGate (`CuratedGateCreateNodeOperatorTest`)

- [ ] Create a node operator via CuratedGate
  - [ ] Provide valid Merkle proof, name, description, manager and reward addresses
  - [ ] Operator is created with `extendedManagerPermissions = true` and metadata stored in MetaRegistry
  - [ ] Second creation attempt from same address reverts (consumed)
- [ ] Create NO via gate with non-default bond curve
  - [ ] NO is assigned the gate's curve (not the default)
- [ ] Invalid proof reverts
- [ ] Set custom tree root/CID (requires `SET_TREE_ROLE` — easyTrack executor)
  - [ ] Previously unlisted address becomes eligible with new proof

## MerkleGateFactory (`CuratedGateFactoryTest`)

- [ ] Create curated gate instance via factory with CuratedGate impl

## MetaRegistry (`MetaRegistryIntegrationTestCurated`)

- [ ] Operator metadata
  - [ ] Set metadata as admin (requires `SET_OPERATOR_INFO_ROLE`)
  - [ ] Set metadata as owner
  - [ ] Owner edits restricted — owner call reverts
  - [ ] Non-owner/non-admin caller reverts
- [ ] Operator groups (requires `MANAGE_OPERATOR_GROUPS_ROLE` — easyTrack executor)
  - [ ] Create operator group
    - [ ] Sub-node-operators with shares summing to 10000 BPS, optional external operators
    - [ ] Operators receive effective weights and become eligible for deposits
  - [ ] Update operator group — change shares/members, weights recalculated
  - [ ] Clear operator group — affected operators lose weight, `depositableValidatorsCount` becomes zero
  - [ ] Operator already in another group — reverts
  - [ ] Shares don't sum to 10000 BPS — reverts
- [ ] Bond curve weights
  - [ ] Set bond curve weight (requires `SET_BOND_CURVE_WEIGHT_ROLE`)
  - [ ] Triggers full deposit info update on module
  - [ ] After refresh, operator effective weights reflect the new curve weight
- [ ] Refresh operator weight (permissionless) — weight recomputed from current bond curve and share

## CuratedModule

- [ ] Submitting keys (`AddValidatorKeysTestCurated`)
  - [ ] ETH
  - [ ] stETH
  - [ ] wstETH
- [ ] Deposit allocation — initial deposits (`ObtainDepositDataTestCurated`, `StakingRouterIntegrationTestCurated`)
  - [ ] Precondition: multiple operators with keys, non-zero weights, deposit info up to date
  - [ ] Deposits are distributed proportionally to operator weights
  - [ ] Operator with zero weight receives no deposits
  - [ ] Second deposit round corrects imbalance from first round
  - [ ] External stake from NOR is accounted for (normalized by 2048 ETH)
  - [ ] Reverts with `DepositInfoIsNotUpToDate()` if deposit info is stale
- [ ] Deposit allocation — top-ups (`StakingRouterIntegrationTestCurated`)
  - [ ] Precondition: operators with deposited keys, non-zero weights and balances
  - [ ] Top-ups via Staking Router `allocateDeposits` are weight-proportional with 1 ETH step
  - [ ] Operators not in request don't inflate shares of included ones (global share baseline)
  - [ ] Capacity capped at `activeValidators * 2048 ETH - currentBalance`
- [ ] Operator balance reporting (`StakingRouterIntegrationTestCurated`)
  - [ ] Staking Router calls `updateOperatorBalances` — balances are stored and affect subsequent allocations
- [ ] Weight-zero depositable gating

  - [ ] Zero operator weight (via clearing group or zero bond curve weight) → no deposits
  - [ ] Restore non-zero weight → deposits resume

- [ ] Addresses (`NoAddressesPermissionsTestCurated`, `NoAddressesBasicPermissionsTestCurated`, `NoAddressesExtendedPermissionsTestCurated`)
  - [ ] Extended permissions = TRUE (default for CuratedGate-created operators)
    - [ ] Change reward address (propose + confirm)
    - [ ] Change reward address (directly from manager via extended permissions)
    - [ ] Change manager address (propose + confirm)
  - [ ] Admin address override (requires `OPERATOR_ADDRESSES_ADMIN_ROLE`)
    - [ ] `changeNodeOperatorAddresses(noId, newManager, newReward)` changes both in one tx
- [ ] Remove keys (`RemoveKeysTestCurated`)
  - [ ] No `keyRemovalCharge` penalty is applied (CuratedModule uses default removal)
  - [ ] Optimistic vetting reset
    - [ ] Upload invalid key
    - [ ] Upload valid key
    - [ ] Key is unvetted
    - [ ] Remove the key
    - [ ] `totalVetted == totalAdded`
- [ ] Pause / resume

  - [ ] Module is resumed in baseline state before pause checks
  - [ ] Pause only Module
    - [ ] NO creation via gates and keys upload is impossible
    - [ ] Oracle works as usual
    - [ ] Rewards claim is possible
  - [ ] Pause Module and Accounting
    - [ ] Oracle works as usual
    - [ ] Rewards claim is impossible
  - [ ] Pause CuratedGate
    - [ ] Can't create node operators using it
  - [ ] Pause Verifier
    - [ ] Can't submit withdrawal/slashed proofs via Verifier (`whenResumed` blocks `processWithdrawalProof`/`processSlashedProof`)
  - [ ] Pause Ejector
    - [ ] Can't eject with strikes proof
    - [ ] Can't eject voluntary

- [ ] Target Limit (`StakingRouterIntegrationTestCurated`)
  - [ ] Set `targetLimitMode` for NO = 1 (soft)
    - [ ] Prepare NO with enough active/depositable validators to exceed planned soft target
    - [ ] Call Staking Router `updateTargetValidatorsLimits(stakingModuleId, noId, 1, targetLimit)` (SR forwards to module's 3-param variant)
    - [ ] NO stops receiving additional stake once target is reached
    - [ ] If NO remains above target, validators are prioritized for exit by WQ demand
    - [ ] Exited keys are reported, withdrawal report submitted via Verifier (external step)
  - [ ] Set `targetLimitMode` for NO = 2 (force)
    - [ ] Prepare NO with enough active/depositable validators to exceed planned force target
    - [ ] Call Staking Router `updateTargetValidatorsLimits(stakingModuleId, noId, 2, targetLimit)` (SR forwards to module's 3-param variant)
    - [ ] NO stops receiving additional stake despite WQ demand
    - [ ] Validators are prioritized for forced exit path
    - [ ] Exited keys are reported, withdrawal report submitted via Verifier (external step)
- [ ] Penalties (general delayed penalty) (`PenaltyIntegrationTestCurated`)

  - [ ] Report general delayed penalty (requires `REPORT_GENERAL_DELAYED_PENALTY_ROLE`)
    - [ ] `reportGeneralDelayedPenalty(noId, bytes32(penaltyType), amount, details)` → locked bond increases by `amount + additionalFine`
  - [ ] Cancel general delayed penalty (requires `REPORT_GENERAL_DELAYED_PENALTY_ROLE`)
    - [ ] `cancelGeneralDelayedPenalty(noId, amountToCancel)` → locked bond decreases
  - [ ] Compensate general delayed penalty (compensation is taken from NO bond)
    - [ ] `compensateGeneralDelayedPenalty(noId)` from NO manager → locked bond decreases
  - [ ] Settle general delayed penalty (requires `SETTLE_GENERAL_DELAYED_PENALTY_ROLE`)
    - [ ] `settleGeneralDelayedPenalty([noId], [maxAmount])` → bond is settled up to `maxAmount`

- [ ] Withdrawals
  - [ ] Simple exit with >= 32 ETH
    - [ ] Exited keys are reported, withdrawal report submitted via Verifier (external step)
    - [ ] Bond is unchanged, excess bond is available
  - [ ] Exit with balance below 32 ETH
    - [ ] Exited keys are reported, withdrawal report submitted via Verifier (external step)
    - [ ] Bond is changed by the balance diff
  - [ ] Exit with voluntary triggerable exit
    - [ ] Node operator calls `ejector.voluntaryEject(noId, keyIndices, refundRecipient)` with required value
    - [ ] `elWithdrawalRequestFee` is not recorded for voluntary exit type
    - [ ] Withdrawal report submitted via Verifier (external step), bond is not changed
  - [ ] Exit with reported strikes penalty
    - [ ] Collect threshold strikes, trigger exit via `processBadPerformanceProof`
    - [ ] `strikesPenalty` and `elWithdrawalRequestFee` (capped by `maxElWithdrawalRequestFee`) are recorded
    - [ ] Withdrawal report submitted via Verifier (external step), bond is changed by penalties + fees
  - [ ] Exit with reported delay fee
    - [ ] Set target limit, wait until delay exceeds `ParametersRegistry.getAllowedExitDelay(curveId)`
    - [ ] Report delay via Staking Router, trigger exit request
    - [ ] `delayFee` and `elWithdrawalRequestFee` are recorded
    - [ ] Withdrawal report submitted via Verifier (external step), bond is changed by fees
  - [ ] Penalty settlement: charge vs burn split
    - [ ] Penalty amount is burned from bond (via `Lido.burnShares`)
    - [ ] Fee amount (`elWithdrawalRequestFee`) is transferred to charge penalty recipient (via `chargeFee`)
    - [ ] `setChargePenaltyRecipient` changes the recipient for subsequent charges
  - [ ] Exit of a slashed validator (combine checks in one scenario given slashing is hard to reproduce)
    - [ ] Validator is marked slashed via `processSlashedProof` through Verifier
    - [ ] Slashed withdrawal is reported via `reportSlashedWithdrawnValidators` (committee path)
    - [ ] `slashingPenalty` (from `WithdrawnValidatorInfo`) is burned unscaled, strikes/delay penalties scaled by exit balance
    - [ ] `elWithdrawalRequestFee` (from `ExitPenaltyInfo`) is charged for the strikes/delay component
    - [ ] If total penalty exceeds bond: `targetLimitMode` set to forced (2) with `targetLimit = 0`, bond debt is created
  - [ ] Historical withdrawal report
    - [ ] Submit historical withdrawal report via Verifier for an older exited key
    - [ ] No double-accounting for previously reported keys

## Deposit info refresh pipeline (`DepositInfoRefreshTestCurated`)

- [ ] Full deposit-info refresh after bond-curve weight update
  - [ ] `MetaRegistry.setBondCurveWeight(curveId, newWeight)` (requires `SET_BOND_CURVE_WEIGHT_ROLE`)
  - [ ] `obtainDepositData` reverts before refresh is complete
  - [ ] `batchDepositInfoUpdate(...)` until complete
  - [ ] `obtainDepositData` succeeds after refresh
- [ ] Deposit-info refresh after bond-curve update on Accounting
  - [ ] `Accounting.updateBondCurve(curveId, ...)` (requires `MANAGE_BOND_CURVES_ROLE`)
  - [ ] Complete `batchDepositInfoUpdate(...)` until done
- [ ] Deposit-info refresh triggered by MetaRegistry group change
  - [ ] Update operator group — weight changes propagate to depositable counts

## Split withdrawn-reporting paths

_No existing integration test suite._

- [ ] Regular vs slashed withdrawn reporting roles
  - [ ] Regular withdrawn report through Verifier path succeeds
  - [ ] Slashed withdrawn report from non-authorized caller reverts
  - [ ] Slashed withdrawn report through authorized path succeeds

## Verifier proof paths

_No existing integration test suite._

- [ ] Slashed validator proof path (`Verifier.processSlashedProof`)
  - [ ] Valid slashed proof applies slashed state
  - [ ] Proof for a non-slashed validator reverts
  - [ ] Paused Verifier blocks proof processing

## Accounting

- [ ] Deposit (`DepositTestCurated`)
  - [ ] ETH
  - [ ] stETH
  - [ ] wstETH
  - [ ] stETH with permit (covered via UI)
  - [ ] wstETH with permit (covered via UI)
- [ ] Claim rewards (`ClaimRewardsTestCurated`)
  - [ ] Claim excess bond
    - [ ] unstETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Can't claim with lock > excess
    - [ ] unstETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Can't claim after burning a part of bond (penalty settling)
    - [ ] unstETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Claim rewards with Merkle proof
    - [ ] unstETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Claim rewards in unstETH (`claimRewardsUnstETH`)
  - [ ] Transfer rewards to bond balance with no claim
- [ ] Add new bond curve
  - [ ] Set new curve for NO
  - [ ] Bond math is changed
- [ ] Update bond curve
  - [ ] Bond math is changed for the NO
- [ ] Bond debt (`AccountingExtrasTestCurated`)
  - [ ] Penalty exceeds bond — debt is created
  - [ ] New deposit covers existing debt
  - [ ] Rewards distribution covers debt
- [ ] Accounting params changes (`AccountingExtrasTestCurated`)
  - [ ] `setChargePenaltyRecipient` changes recipient of charged amount
  - [ ] `setBondLockPeriod` changes retention period for newly created locks
- [ ] Fee splits (`FeeSplitsTestCurated`)
  - [ ] Set fee splits for NO (`updateFeeSplits` with recipients and shares in BP)
    - [ ] Only NO owner can call
    - [ ] Total shares can be less than 10000 BP (remainder stays on bond)
  - [ ] Update fee splits is blocked while `getPendingSharesToSplit(noId) > 0`
    - [ ] Set splits, earn rewards via oracle report
    - [ ] Attempt `updateFeeSplits` — blocked
    - [ ] Call `pullAndSplitFeeRewards` to distribute pending shares
    - [ ] Attempt `updateFeeSplits` again — succeeds
  - [ ] Update fee splits is blocked while undistributed rewards exist
    - [ ] Set splits, oracle reports new rewards, attempt `updateFeeSplits` without pulling rewards first — blocked
    - [ ] Call `pullAndSplitFeeRewards` to pull and distribute rewards
    - [ ] Attempt `updateFeeSplits` again — succeeds
  - [ ] Pull and distribute split rewards — recipients receive correct shares
  - [ ] Remove fee splits (call `updateFeeSplits` with empty array after pending is zero)
  - [ ] Splits do not reduce penalty amounts
- [ ] Custom rewards claimer (`AccountingExtrasTestCurated`)
  - [ ] NO owner/manager sets custom claimer via `setCustomRewardsClaimer`
  - [ ] Custom claimer can trigger reward claim (rewards go to NO reward address)

## FeeOracle (`OracleTestCurated`)

- [ ] Oracle flow

  - [ ] Oracle contract paused, offchain oracle is OK
  - [ ] Zero report (no operators) (if possible to check)
  - [ ] Report with 1 operator (if possible to check)
  - [ ] Report with multiple operators
  - [ ] Report with multiple operators but one under average performance
  - [ ] Report after a missed frame
  - [ ] Report the same tree (no attestations within frame) (if possible to check)

- [ ] Strikes Oracle flow
  - [ ] Empty report
  - [ ] Empty report that wipes previous one
  - [ ] Report with data

## FeeDistributor (`FeeDistributorExtrasTestCurated`)

- [ ] Set rebate recipient
- [ ] Rebate mechanism
  - [ ] Oracle report includes non-zero `rebate` value — rebate recipient receives expected amount
  - [ ] Report with `distributed == 0` and `rebate > 0` reverts with `InvalidReportData`
- [ ] Historical distribution data
  - [ ] After several oracle reports, `getHistoricalDistributionData(index)` returns correct per-report data

## ValidatorStrikes

_No existing integration test suite._

- [ ] Process invalid proof — reverts
- [ ] Process proof with not enough strikes — reverts
- [ ] Process proof (preferably with refund recipient)
  - [ ] Triggerable exit event emitted
  - [ ] Strikes exit penalty and EL withdrawal request fee recorded (bounded by `maxElWithdrawalRequestFee`)
  - [ ] Extra fees refunded
- [ ] Process multiproof for multiple keys
- [ ] Process proof second time for the same key — exit event emitted, penalties/fees do not increase
- [ ] Process multiproof when paid triggerable withdrawal fee > `maxElWithdrawalRequestFee` (if possible; network-conditions specific)

## Ejector (`EjectionTestCurated`)

- [ ] Voluntary eject by arbitrary array
  - [ ] Non-contiguous `keyIndices`, explicit `refundRecipient`
  - [ ] Triggerable exit event emitted, extra fees refunded
  - [ ] No `elWithdrawalRequestFee` recorded for voluntary exit type
- [ ] Voluntary eject second time for the same key — exit event emitted, extra fees refunded, penalties not changed
- [ ] Voluntary eject with duplicate key index in one request — reverts with `DuplicateKeyIndex()`

## ParametersRegistry (`ParametersRegistryTestCurated`)

- [ ] Change key removal charge
- [ ] Change general delayed penalty additional fine
- [ ] Set keys limit
  - [ ] Nothing changes for NO with more keys, but restricted from uploading more
  - [ ] Can't upload keys over limit
- [ ] Set queue config
  - [ ] Note: CuratedModule does not use a deposit queue; queue config affects priority/maxDeposits metadata only
- [ ] Set reward share data
- [ ] Set performance leeway
- [ ] Set performance coefficients
- [ ] Set strikes params
  - [ ] Go 3 -> 2, key with 2 strikes becomes available to eject
  - [ ] Go 3 -> 4, key with 3 strikes should revert now
- [ ] Set allowed exit delay
- [ ] Set exit delay fee
  - [ ] Existing recorded penalties should not change
- [ ] Set bad performance penalty (for strikes)
  - [ ] Existing recorded penalties should not change
- [ ] Set max EL withdrawal request fee
  - [ ] Value is persisted for curve

## GateSeal (`GateSealTestCurated`)

- [ ] Seal all sealable contracts
  - [ ] Seal Module — contract is paused
  - [ ] Seal Accounting — contract is paused
  - [ ] Seal Oracle — contract is paused
  - [ ] Seal Verifier — contract is paused
  - [ ] Seal Ejector — contract is paused
- [ ] Seal only CuratedGate
  - [ ] `gateSeal.seal([curatedGate])` from committee account
  - [ ] CuratedGate is paused
  - [ ] Module/Accounting/Oracle/Verifier remain resumed

## DSM related

- [ ] Deposit
  - [ ] Curated Module deposit preparation
    - [ ] Add operator with keys via CuratedGate
    - [ ] Ensure operator is in a group with non-zero weight
    - [ ] Add keys to existing operator
  - [ ] Perform at least 1 deposit
  - [ ] Check the deposit tx
  - [ ] Wait for validator activation
  - [ ] Wait for the AO report and check it
- [ ] Unvetting
  - [ ] Invalid signature
    - [ ] Check that UI blocks invalid signature upload
    - [ ] Bypass UI and upload invalid signature
    - [ ] Check that the key was unvetted
  - [ ] Duplicate
    - [ ] Upload duplicates within 1 operator

## Auth requirements summary

| Action                         | Required role / caller                          | Typical holder                     |
| ------------------------------ | ----------------------------------------------- | ---------------------------------- |
| Create NO via CuratedGate      | Valid Merkle proof (permissionless with proof)  | Allowlisted address                |
| Set gate tree root/CID         | `SET_TREE_ROLE` on gate                         | easyTrack executor                 |
| Pause CuratedGate              | `PAUSE_ROLE` on gate                            | curatedGatePauseManager            |
| Resume CuratedGate             | `RESUME_ROLE` on gate                           | (none initially)                   |
| Create/update operator groups  | `MANAGE_OPERATOR_GROUPS_ROLE` on MetaRegistry   | easyTrack executor                 |
| Set bond curve weight          | `SET_BOND_CURVE_WEIGHT_ROLE` on MetaRegistry    | (none initially; must be granted)  |
| Set operator metadata (admin)  | `SET_OPERATOR_INFO_ROLE` on MetaRegistry        | Each gate + setOperatorInfoManager |
| Change NO addresses (admin)    | `OPERATOR_ADDRESSES_ADMIN_ROLE` on module       | (none initially; must be granted)  |
| Report general delayed penalty | `REPORT_GENERAL_DELAYED_PENALTY_ROLE` on module | Designated reporter                |
| Settle general delayed penalty | `SETTLE_GENERAL_DELAYED_PENALTY_ROLE` on module | Designated settler                 |
| Manage bond curves             | `MANAGE_BOND_CURVES_ROLE` on Accounting         | Governance                         |
| Set bond curve for NO          | `SET_BOND_CURVE_ROLE` on Accounting             | Gates with non-default curve       |
| Set charge penalty recipient   | `DEFAULT_ADMIN_ROLE` on Accounting              | Aragon agent                       |
| GateSeal                       | Sealing committee member                        | GateSeal committee                 |
| Staking Router calls           | `STAKING_ROUTER_ROLE` on module                 | Staking Router contract            |
| Verifier calls                 | `VERIFIER_ROLE` on module                       | Verifier contract                  |
