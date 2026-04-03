# Test locked bond

Walk through the locked bond (general delayed penalty) lifecycle on a local fork.

## Prerequisites

Create an operator with a deposited key (see [keys-test.md](keys-test.md) steps 1–4).
Assume operator id is `0`.

> Note: check operator state anytime with `just operator-info 0`.

## 1. Report penalty

```bash
just report-penalty 0 1.3
```

Locks `1.3 + 0.1` (additional fine) = 1.4 ETH of the operator's bond. The lock period timer starts now.

## 2. Cancel penalty

```bash
just cancel-penalty 0 0.5
```

Reduces locked bond by 0.5 ETH. Remaining locked: 0.9 ETH.

Cancelling the full locked amount unlocks the bond entirely:

```bash
just cancel-penalty 0 0.9
```

No more locked bond.

## 3. Compensate penalty

Report a new penalty first:

```bash
just report-penalty 0 1
```

Locked bond: 1.1 ETH (1 + 0.1 fine).

Compensate uses excess bond (bond above the required amount) to pay the penalty. If excess bond is 0, compensate does nothing.

Try compensating without extra bond first:

```bash
just compensate-penalty 0
```

Nothing happens — no excess bond available.

Top up the bond and compensate:

```bash
just add-bond 0 0.5
just compensate-penalty 0
```

Pays 0.5 ETH from excess bond toward the locked amount. Remaining locked: 0.6 ETH.

## 4. Settle penalty

Report a new penalty:

```bash
just report-penalty 0 2
```

Locked bond: 0.6 (remaining) + 2 + 0.1 (fine) = 2.7 ETH. New reports stack on existing lock.

Settle — a privileged role finalizes the penalty, burning the locked bond:

```bash
just settle-penalty 0
```

Bond reduces by 2.7 ETH. No more locked bond. Insufficient bond appears if the operator didn't have enough excess bond to cover the locked amount.

## 5. Warp past lock period

Report a penalty:

```bash
just report-penalty 0 1
```

Locked bond: 1.1 ETH.

Advance time past the bond lock period:

```bash
just warp 60
```

The lock has expired. The locked amount is no longer enforceable — settle/compensate has no effect to bond:

```bash
just settle-penalty 0
```

Bond is unchanged. The expired lock is removed.
