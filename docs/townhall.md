# Steps

## Setup (already done)

```bash
./prepare-modules.sh
./update-curated-trees.sh
just seed-cm
just snapshot
```

## Add 100 eth balance to wallet

```bash
just topup 0x97ca715a08bA67E4Efe56Aa43e5A756EE66f8Ae3
```

## After create operator and upload keys

```bash
just create-operator-group {id} 100
just deposit-keys 100
```

## Topup key balance

```bash
just key-topup {id} 0 1000
just cl-activate {id} 0 1032
```

## Report rewards

```bash
just report-rewards
```

## Suboperators

```bash
just reset-operator-group {id}
just create-operator-groupjust create-operator-group {id} 50 {id2} 50
```

increase potential capacity
