# Test keys

Walk through key lifecycle states on a local fork.

## 1. Create operator

```bash
just create-curated-operator
```

Creates operator without keys. Assume operator id is `0`.

> Note: check operator state anytime with `just operator-info 0`.

> Note: check operator keys anytime with `just operator-keys 0`.

## 2. Add key

```bash
just add-keys 0 1
```

Operator has 1 `DEPOSITABLE` key.

## 3. Add operator to group

```bash
just create-operator-group 0 100
```

## 4. Deposit key

```bash
just deposit-keys 100
```

Key becomes `ACTIVATION_PENDING`.

## 5. Report penalty

```bash
just report-penalty 0 1.3
```

Operator has locked bond for 1.4 ETH (1.3 + 0.1 fee).

## 6. Settle penalties

```bash
just settle-penalty 0
```

Bond reduces by 1.4 ETH. No more locked bond but insufficient bond appears. Key becomes `UNBONDED`.

## 7. Request exit

```bash
just exit-request 0 0
```

Key becomes `EXIT_REQUESTED`.

## 8. Make key active

Start the CL mock server:

```bash
just cl-start
```

> Note: add `CL_API_URLS_560048=http://127.0.0.1:5052` to csm-widget env.

```bash
export PUBKEY=$(just get-pubkey 0 0)
just cl-set $PUBKEY active_ongoing
```

Key becomes `ACTIVE` (still requested to exit).

> Note: all valid CL mock statuses — `just cl-statuses`.

## 9. Slash key

```bash
just cl-set $PUBKEY active_slashed
```

Key becomes `EXITING` and `SLASHED`.

## 10. Exit key

```bash
just cl-set $PUBKEY exited_slashed
```

Key becomes `EXITED` (and `SLASHED`).

## 11. Withdraw key

```bash
just cl-set $PUBKEY withdrawal_done_slashed
```

Optionally finalize withdrawal onchain:

```bash
just withdraw-key 0 0
```


## 12. Invalidate keys

Add 2 more keys:

```bash
just add-keys 0 2
```

Operator now has 3 keys, last 2 are `DEPOSITABLE`. Unvet them:

```bash
just unvet-key 0 1
```

One key becomes `INVALID`, the other `UNCHECKED`.

## 13. Duplicate key

Keys in `INVALID` or `UNCHECKED` status are marked `DUPLICATED` if CL already has the pubkey.

```bash
export PUBKEY=$(just get-pubkey 0 1)
just cl-set $PUBKEY active_ongoing
```

Key becomes `DUPLICATED`.

## 14. Remove invalid key

```bash
just remove-key 0 1
```

Removes the `INVALID`/`DUPLICATED` key. Remaining `UNCHECKED` key become `DEPOSITABLE` until unveted again.
