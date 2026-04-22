# Steps

## Setup (already done)

```bash
./prepare-modules.sh
just snapshot
just seed-cm
just snapshot
```

after this - update devnet.json in csm-widget

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
just topup-active-keys {id}
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
