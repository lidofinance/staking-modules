# Steps

## Setup (already done)

```bash
./prepare-modules.sh
./update-curated-trees.sh
just seed-cm
just snapshot
```

## Add address to curated gates and add 100 eth to wallet balance

Add files to gate whitelist

```bash
echo {address} >> addresses1
echo {address} >> addresses2
```

Update gates onchain

```bash
./update-curated-trees.sh
```

Topup wallet address

```bash
just topup {address}
```

## After create operator and upload keys

```bash
just create-operator-group {id} 100
just deposit-keys 100
```

## Topup key balance

for first operator key (`0`)

```bash
just key-topup {id} 0 2016
just cl-activate {id} 0
```

## Report rewards

```bash
just report-rewards
```

## Suboperators

```bash
just create-operator-group {id} 50 {id2} 50
```

increase potential capacity
