The document describes what should be tested during `testnet` or `devnet` with CSM v3 contracts on live networks.

## Scope and constraints

- Adaptation of existing CSM v2 scenarios plus explicit v3-only scenario families listed below.
- Use live network calls only: no impersonation, no prank/cheatcodes.
- Use real deployed addresses from the selected chain deployment artifact.
- This manual suite is action-driven: each scenario should include a real transaction and an observable effect.
- Static/immutable/default deploy configuration checks belong to deployment test suites, not here.
- State baseline for this suite is post-vote only (module stack already live/resumed).

## v3 adaptation notes

- `EL rewards stealing penalty` scenarios are replaced by `general delayed penalty` scenarios.
- `maxWithdrawalRequestFee` is renamed to `maxElWithdrawalRequestFee`.
- `exit delay penalty` naming is now `exit delay fee`.
- Exit request can originate from VEBO/external pathways; CSM tool submission to `Verifier` is treated as an external step.
- `Ejector` flow is array-based (`keyIndices`); old `range` flow should be treated as contiguous array input.

## Execution pattern for v3 exit-related scenarios

- [ ] Trigger exit cause (target limit, voluntary trigger, strikes, or delay flow).
- [ ] Report exited keys in CSM from Staking Router (`reportStakingModuleExitedValidatorsCountByNodeOperator`).
- [ ] Wait for CSM tool to submit withdrawal report through `Verifier` (external step).
- [ ] After verifier tx finalization, check module/accounting/exit-penalties outcomes.

## New v3-only scenarios

### Deposit info refresh pipeline (`DepositInfoRefreshTestCSM`)

- [ ] Full deposit-info refresh after bond-curve update
  - [ ] `Accounting.updateBondCurve(curveId, ...)` from `MANAGE_BOND_CURVES_ROLE` account
  - [ ] `cleanDepositQueue(maxItems)` reverts before refresh is complete
  - [ ] `batchDepositInfoUpdate(...)` until complete
  - [ ] `cleanDepositQueue(maxItems)` succeeds after refresh

### Split withdrawn-reporting paths

- [ ] Regular vs slashed withdrawn reporting roles
  - [ ] Regular withdrawn report through Verifier path succeeds
  - [ ] Slashed withdrawn report from non-authorized caller reverts
  - [ ] Slashed withdrawn report through authorized path succeeds

### Verifier proof paths

- [ ] Slashed validator proof path (`Verifier.processSlashedProof`)
  - [ ] Valid slashed proof applies slashed state
  - [ ] Proof for a non-slashed validator reverts
  - [ ] Paused Verifier blocks proof processing

### Permissionless Gate

- [ ] It is allowed to create a node operator permissionless (`PermissionlessCreateNodeOperatorTest`)
  - [ ] Using ETH
  - [ ] Using stETH
  - [ ] Using wstETH
  - [ ] Using stETH permit path
  - [ ] Using wstETH permit path

### Vetted Gate

- [ ] Only vetted member can create NO (`VettedGateCreateNodeOperatorTest`)
  - [ ] Using ETH
  - [ ] Using stETH
  - [ ] Using wstETH
  - [ ] Invalid proof reverts for ETH/stETH/wstETH creation paths
- [ ] Vetted member is able to claim the curve if on the default bond curve (`VettedGateMiscTest`)
  - [ ] Curve claim updates NO bond curve and creates claimable bond delta
  - [ ] Invalid proof keeps NO on default curve and does not consume member
- [ ] Set custom tree root/CID (`VettedGateMiscTest`)

### MerkleGateFactory (v3)

- [ ] Create vetted gate instance via factory with VettedGate impl (`VettedGateFactoryTest`)
- [ ] Create curated gate instance via factory with CuratedGate impl (`CuratedGateFactoryTest`)

### CSModule

- [ ] Submitting keys (`AddValidatorKeysTestCSM`)
  - [ ] ETH
  - [ ] stETH
  - [ ] wstETH
- [ ] Deposit queue maintenance in v3 (`CleanDepositQueueTestCSM`)

  - [ ] Precondition is to have a node operator with keys represented in the queue
  - [ ] `cleanDepositQueue(maxItems)` removes only stale batches with no depositable keys
  - [ ] Repeat call is idempotent (no unexpected second effect)

- [ ] Addresses (`NoAddressesPermissionsTestCSM`)
  - [ ] Extended permissions = FALSE
    - [ ] Change reward address (propose + confirm)
    - [ ] Change manager address (propose + confirm)
    - [ ] Reset manager address
  - [ ] Extended permissions = TRUE
    - [ ] Change reward address (propose + confirm)
    - [ ] Change reward address (directly from manager via extended permissions)
    - [ ] Change manager address (propose + confirm)
- [ ] Remove keys (`RemoveKeysTestCSM`)
  - [ ] No penalty when `keyRemovalCharge` = 0
  - [ ] Penalty applied when `keyRemovalCharge` > 0
  - [ ] Optimistic vetting reset
    - [ ] Upload invalid key
    - [ ] Upload valid key
    - [ ] Key is unvetted
    - [ ] Remove the key
    - [ ] `totalVetted == totalAdded`
    - [ ] All keys are in the queue
- [ ] Pause / resume

  - [ ] Module is resumed in baseline state before pause checks
  - [ ] Pause only Module
    - [ ] NO creation via gates and keys upload is impossible
    - [ ] Oracle works as usual
    - [ ] Rewards claim is possible
  - [ ] Pause Module and Accounting
    - [ ] Oracle works as usual
    - [ ] Rewards claim is impossible
  - [ ] Pause Vetted Gate
    - [ ] Can't create node operators using it
    - [ ] Can't claim gate curve
  - [ ] Pause Verifier
    - [ ] Can't submit withdrawal/slashed proofs via Verifier (`whenResumed` blocks `processWithdrawalProof`/`processSlashedProof`)
  - [ ] Pause Ejector
    - [ ] Can't eject with strikes proof
    - [ ] Can't eject voluntary

- [ ] Target Limit
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
- [ ] Penalties (general delayed penalty) (`PenaltyIntegrationTestCSM`)

  - [ ] Report general delayed penalty
    - [ ] `reportGeneralDelayedPenalty(noId, bytes32(penaltyType), amount, details)` → locked bond increases by `amount + additionalFine`
  - [ ] Cancel general delayed penalty
    - [ ] `cancelGeneralDelayedPenalty(noId, amountToCancel)` → locked bond decreases
  - [ ] Compensate general delayed penalty (compensation is taken from NO bond)
    - [ ] `compensateGeneralDelayedPenalty(noId)` from NO manager → locked bond decreases
  - [ ] Settle general delayed penalty
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

### Accounting

- [ ] Deposit (`DepositTestCSM`)
  - [ ] ETH
  - [ ] stETH
  - [ ] wstETH
  - [ ] stETH with permit (covered via UI)
  - [ ] wstETH with permit (covered via UI)
- [ ] Claim rewards (`ClaimRewardsTestCSM`)
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
- [ ] Bond debt (`AccountingExtrasTestCSM`)
  - [ ] Penalty exceeds bond — debt is created
  - [ ] New deposit covers existing debt
  - [ ] Rewards distribution covers debt
- [ ] Accounting params changes (`AccountingExtrasTestCSM`)
  - [ ] `setChargePenaltyRecipient` changes recipient of charged amount
  - [ ] `setBondLockPeriod` changes retention period for newly created locks
- [ ] Fee splits
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
- [ ] Custom rewards claimer (`AccountingExtrasTestCSM`)
  - [ ] NO owner/manager sets custom claimer via `setCustomRewardsClaimer`
  - [ ] Custom claimer can trigger reward claim (rewards go to NO reward address)

### FeeOracle

- [ ] CSM Oracle flow (`OracleTestCSM`)

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

### FeeDistributor (`FeeDistributorExtrasTestCSM`)

- [ ] Set rebate recipient
- [ ] Rebate mechanism
  - [ ] Oracle report includes non-zero `rebate` value — rebate recipient receives expected amount
  - [ ] Report with `distributed == 0` and `rebate > 0` reverts with `InvalidReportData`
- [ ] Historical distribution data
  - [ ] After several oracle reports, `getHistoricalDistributionData(index)` returns correct per-report data

### ValidatorStrikes

- [ ] Process invalid proof — reverts
- [ ] Process proof with not enough strikes — reverts
- [ ] Process proof (preferably with refund recipient)
  - [ ] Triggerable exit event emitted
  - [ ] Strikes exit penalty and EL withdrawal request fee recorded (bounded by `maxElWithdrawalRequestFee`)
  - [ ] Extra fees refunded
- [ ] Process multiproof for multiple keys
- [ ] Process proof second time for the same key — exit event emitted, penalties/fees do not increase
- [ ] Process multiproof when paid triggerable withdrawal fee > `maxElWithdrawalRequestFee` (if possible; network-conditions specific)

### Ejector

- [ ] Voluntary eject by arbitrary array (`EjectionTestCSM`)
  - [ ] Non-contiguous `keyIndices`, explicit `refundRecipient`
  - [ ] Triggerable exit event emitted, extra fees refunded
  - [ ] No `elWithdrawalRequestFee` recorded for voluntary exit type
- [ ] Voluntary eject second time for the same key — exit event emitted, extra fees refunded, penalties not changed
- [ ] Voluntary eject with duplicate key index in one request — reverts with `DuplicateKeyIndex()`

### ParametersRegistry (`ParametersRegistryTestCSM`)

- [ ] Change key removal charge
- [ ] Change general delayed penalty additional fine
- [ ] Set keys limit
  - [ ] Nothing changes for NO with more keys, but restricted from uploading more
  - [ ] Can't upload keys over limit
- [ ] Set queue config
  - [ ] Upload keys to lower-priority queue
  - [ ] Set queue priority higher
  - [ ] Upload more keys
  - [ ] Receive deposits, keys from the new higher-priority batch go first
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

### GateSeal

- [ ] Seal all sealable contracts (`GateSealTestCSM`)
  - [ ] Seal Module — contract is paused
  - [ ] Seal Accounting — contract is paused
  - [ ] Seal Oracle — contract is paused
  - [ ] Seal Verifier — contract is paused
- [ ] Seal only Vetted Gate (`GateSealVettedTest`)
  - [ ] `gateSeal.seal([vettedGate])` from committee account
  - [ ] Vetted Gate is paused
  - [ ] Module/Accounting/Oracle/Verifier remain resumed

### DSM related

- [ ] Deposit
  - [ ] CSM deposit preparation
    - [ ] Add operator with keys
    - [ ] Generate keys
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
