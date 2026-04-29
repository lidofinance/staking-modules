The document describes what should be tested during `testnet` or `devnet` with CSM v2 contracts.

### Permissionless Gate

- [ ] It is allowed to create a node operator permissionless (`PermissionlessCreateNodeOperatorTest`)
  - [ ] Using ETH
  - [ ] Using stETH
  - [ ] Using wstETH

### Vetted Gate

- [ ] Only vetted member can create NO (`VettedGateCreateNodeOperatorTest`)
  - [ ] Using ETH
  - [ ] Using stETH
  - [ ] Using wstETH
- [ ] Vetted member is able to claim the curve if on the default bond curve (`VettedGateMiscTest`)
  - [ ] Check relevant curve parameters applied
- [ ] Set custom tree root (`VettedGateMiscTest`)
- [ ] Refferal season (`VettedGateMiscTest`)
  - [ ] Activate refferal season
  - [ ] Create a node operator with refferal address
  - [ ] Create refferal node operator and claim refferal curve
  - [ ] Do steps above exept for the referral curve claim
  - [ ] Deactivate refferal season
  - [ ] Check that it is not possible to claim refferal curve again using another address

### VettedGateFactory

- [ ] Create new instance (`VettedGateFactoryTest`)

### CSModule

- [ ] Submiting keys (`AddValidatorKeysTest`)
  - [ ] ETH
  - [ ] stETH
  - [ ] wstETH
- [ ] Migrate to priority queue (will skip in autotests for now)

  - [ ] Precondition is to have a node operator with keys in the queue
  - [ ] Only maxDeposits keys should be migrated
  - [ ] Can't call twice

- [ ] Addresses (`NoAddressesPermissionsTest`)
  - [ ] Extended permissions = FALSE
    - [ ] Change reward address
    - [ ] Change manager address
    - [ ] Reset manager address
  - [ ] Extended permissions = TRUE
    - [ ] Change reward address (two phased)
    - [ ] Change reward address (from manager)
    - [ ] Change manager address
- [ ] Remove keys (`RemoveKeysTest`)
  - [ ] Check that penalty wasn't applied when `keyRemovalCharge` = 0
  - [ ] Check that penalty was applied when `keyRemovalCharge` > 0
  - [ ] Optimistic vetting reset
    - [ ] Upload invalid key
    - [ ] Upload valid key
    - [ ] Check that the key was unvetted
    - [ ] Remove the key
    - [ ] Check that totalVetted == totalAdded
    - [ ] Check that all keys are in the queue
- [ ] Pause (is covered with unit tests)

  - [ ] Pause only Module
    - [ ] NO creation via Gates and keys upload is impossible
    - [ ] Oracle works as usual
    - [ ] Rewards claim is possible
  - [ ] Pause Module and Accounting
    - [ ] Oracle works as usual
    - [ ] Rewards claim is imposible
  - [ ] Pause Vetted Gate
    - [ ] Can't create node operators using it
    - [ ] Can't claim gate curve
    - [ ] Can't claim refferral curve
  - [ ] Pause CSVerifier
    - [ ] Can't report withdrawals
  - [ ] Pause CSEjector
    - [ ] Can't eject with strikes proof
    - [ ] Can't eject voluntary

- [ ] Target Limit
  - [ ] Set `targetLimitMode` for NO = 1 (soft)
    - [ ] depositable is changed by `targetLimit`
    - [ ] `targetLimit` is reached, the operator stops receiving new stakes by WQ demand
    - [ ] exceeds `targetLimit`, validators are prioritized for exit by WQ demand
    - [ ] Withdrawal is reported by CSM tool
  - [ ] Set `targetLimitMode` for NO = 2 (force)
    - [ ] depositable is changed by `targetLimit`
    - [ ] `targetLimit` is reached, the operator stops receiving new stakes despite WQ demand
    - [ ] exceeds `targetLimit`, validators are prioritized for exit despite WQ demand
    - [ ] Withdrawal is reported by CSM tool
- [ ] Penalties

  - [ ] MEV stealing report
    - [ ] Lock has value before `bondLock.until`
    - [ ] Lock has 0 value after `bondLock.until`
  - [ ] MEV stealing settle
    - [ ] Burns the lock from bond before `bondLock.until`
    - [ ] Burns nothing after `bondLock.until`
  - [ ] MEV stealing compensate
  - [ ] MEV stealing cancel

- [ ] Withdrawals
  - [ ] Simple exit with >= 32 ETH
    - [ ] VEBO reported exited validator
    - [ ] Withdrawal is reported by CSM tool
    - [ ] Bond is unchanged
    - [ ] Excess bond is available
  - [ ] Exit with balance below 32 ETH
    - [ ] VEBO reported exited validator
    - [ ] Withdrawal is reported by CSM tool
    - [ ] Bond is changed by the balance diff
  - [ ] Exit with voluntary triggerable exit
    - [ ] Triggerable exit is called by the node operator
    - [ ] `withdrawalRequestFee` is recorder with zero value
    - [ ] VEBO reported exited validator
    - [ ] Withdrawal is reported by CSM tool
    - [ ] Bond is not changed
  - [ ] Exit with reported strikes penalty
    - [ ] Collect 3 strikes by the underperforming for 3 frames
    - [ ] Triggerable exit is reported permissionless with strikes proof
    - [ ] `strikesPenalty` is recorded
    - [ ] `withdrawalRequestFee` is recorded
    - [ ] VEBO reported exited validator
    - [ ] Withdrawal is reported by CSM tool
    - [ ] Bond is changed by amount of the `CSParametersRegistry.getStrikesPenalty` + `triggerableExitFee`
  - [ ] Exit with reported delay penalty
    - [ ] Set target limit to trigger the VEBO event
    - [ ] Wait until the exit is being delayed (`CSParametersRegistry.getAllowedExitDelay`)
    - [ ] Delay is reported permissionless via some offchain bot (TODO specify bot)
    - [ ] Triggerable exit is reported permissionless with specified exitType = 1 (non-zero means charge it from the bond)
    - [ ] `delayPenalty` is recorded
    - [ ] `withdrawalRequestFee` is recorded
    - [ ] VEBO reported exited validator
    - [ ] Withdrawal is reported by CSM tool
    - [ ] Bond is changed by amount of the `CSParametersRegistry.getExitDelayPenalty` + `triggerableExitFee`
  - [ ] Historical withdrawal report

### CSAccounting

- [ ] Deposit (`DepositTest`)
  - [ ] ETH
  - [ ] stETH
  - [ ] WstETH
- [ ] Claim rewards (`ClaimRewardsTest`)
  - [ ] Claim excess bond
    - [ ] ETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Can't claim with lock > excess
    - [ ] ETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Can't claim after burning a part of bond (penalty settling)
    - [ ] ETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Claim rewards with Merkle proof
    - [ ] ETH
    - [ ] stETH
    - [ ] wstETH
  - [ ] Transfer rewards to bond balance with no claim
- [ ] Add new bond curve
  - [ ] Setting new curve for NO
  - [ ] Bond math is changed
- [ ] Update bond curve
  - [ ] Bond math is changed for the NO
- [ ] Accounting params changings
  - [ ] `setChargePenaltyRecipient` changes a recipient of charged amount
  - [ ] `setBondLockPeriod` changes retention period for a new created locks

### CSFeeOracle

- [ ] CSM Oracle flow // TODO update regarding new coeffs for attestations/etc

  - [ ] Oracle contract paused. Offchain oracle is OK
  - [ ] The initial epoch in set to FAR_FUTURE_EPOCH. Oracle doesn't collect data.
  - [ ] The initial epoch in the future. Oracle collects data.
  - [ ] Zero report (no operators) (if possible to check)
  - [ ] Report with 1 operator (if possible to check)
  - [ ] Report with multiple operators
  - [ ] Report with multiple operators but one under avg performance
  - [ ] Report after a missed frame
  - [ ] Report the same tree (no attestations within frame) (if possible to check)
  - [ ] Change frame size. Offchain part works properly.

- [ ] Strikes Oracle flow
  - [ ] Empty report
  - [ ] Empty report that wipes previous one
  - [ ] Report with data

### CSFeeDistributor

- [ ] Set Rebate recipient

### CSStrikes

- [ ] Process invalid proof
- [ ] Process proof with not enough strikes
- [ ] Process proof (preferably with refund recipient)
  - [ ] Triggerable exit event emited (core contracts)
  - [ ] Strikes exit penalty recorded
  - [ ] Triggerable exit fee recorded
  - [ ] Extra fees refunded
- [ ] Process multiproof
- [ ] Process proof second time for the same key
  - [ ] Triggerable exit event emited (core contracts)
  - [ ] Exit penalties should not change
- [ ] Process multiproof when triggerable exit fee more than max withdrawal request fee (if possible. specific network conditions)
  - [ ] Triggerable exit fee equals to max withdrawal request fee

### CSEjector

- [ ] Voluntary eject (by range)
  - [ ] Triggerable exit event emited (core contracts)
  - [ ] Extra fees refunded
  - [ ] No triggerable exit fees recorded (isValue=true, value=0)
- [ ] Voluntary eject (by array)
  - [ ] Triggerable exit event emited (core contracts)
  - [ ] Extra fees refunded
  - [ ] No triggerable exit fees recorded (isValue=true, value=0)
- [ ] Voluntary eject second time for the same key
  - [ ] Triggerable exit event emited (core contracts)
  - [ ] Extra fees refunded
  - [ ] Exit penalties not changed

### CSParametersRegistry

- [ ] Change key removal charge
- [ ] Change EL rewards penalty additional fine
- [ ] Set keys limit
  - [ ] Nothing changed for node operator with more keys but restricted to upload more
  - [ ] Can't upload keys over limit
- [ ] Set Queue config
  - [ ] Upload keys to less priority queue
  - [ ] Set queue priority higher
  - [ ] Upload more keys
  - [ ] Receive deposits. Keys for new queue batch should go first
- [ ] Set rewards share data
- [ ] Set performance leeway
- [ ] Set performance coeffs
- [ ] Set strikes params
  - [ ] Go 3 -> 2 = key with 2 strikes becomes available to eject
  - [ ] Go 3 -> 4 = key with 3 strikes should revert now
- [ ] Set allowed exit delay
- [ ] Set exit delay penalties
  - [ ] existing recorded penalties should not change
- [ ] Set bad performance penalty (for strikes)
  - [ ] existing recorded penalties should not change
- [ ] Set max withdrawal request fee

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
    - [ ] Check that UI block invalid signature upload
    - [ ] Bypass UI and upload invalid signature
    - [ ] Check that the key was unvetted
  - [ ] Duplicate
    - [ ] Upload duplicates within 1 operator
      - [ ] Check uvetting
    - [ ] Upload duplicate with the other CSM operator
      - [ ] Check uvetting
    - [ ] Upload duplicate from the other module
      - [ ] Check uvetting

### GateSeal

- [ ] Seal CSModule. Contract is paused
- [ ] Seal CSAccounting. Contract is paused
- [ ] Seal CSFeeOracle. Contract is paused
- [ ] Seal CSVerifier. Contract is paused
- [ ] Seal VettedGate. Contract is paused
- [ ] Seal CSEjector. Contract is paused

### EasyTrack

- [ ] Check calling settling the penalty using ET
