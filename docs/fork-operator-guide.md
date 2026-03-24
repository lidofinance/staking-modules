# Fork Operator Lifecycle Guide

Managing node operators on a local anvil fork for CuratedModule.

## Prerequisites

set env to work with CM

```bash
# .env
DEPLOY_CONFIG=./artifacts/local/curated/deploy-hoodi.json
```

## Commands

### Create operator via curated gate

```bash
# Create operator through gate 0, no keys
just create-curated-operator

# Create operator through gate 0 with 3 keys
just create-curated-operator 0 3

# Create operator through gate 1
just create-curated-operator 1
```

Temporarily swaps the gate's Merkle tree to include a fresh operator address, creates the operator, optionally adds keys with auto-calculated bond, then restores the original tree root/CID. The gate is auto-resumed if paused.

### Operator groups

Operators require a MetaRegistry group assignment with non-zero weight before keys become depositable. Without a group, `depositableValidatorsCount` is forced to 0.Percents in a group must sum to 100.

```bash
# Assign operator 0 with 100% weight
just create-operator-group 0 100

# Multi-operator group: operator 1 gets 90%, operator 2 gets 10%
just create-operator-group 1 90 2 10

# Remove operator from its group
just reset-operator-group <noId>
```

### Add keys

```bash
just add-keys <noId> <keysCount>
```

Adds keys to an existing operator. Bond is auto-calculated and paid.

### Deposit keys

```bash
just deposit-keys <count>
```

Deposits up to `count` depositable keys across all operators via Staking Router. Keys move from the deposit queue to the Deposit Contract.

### Increase effective balance

```bash
just key-topup <noId> <activeKeyIndex> <amountEth>
```

Increases allocated balance for a single active key (1-based index). Use to simulate top-ups, consolidations, or CL rewards.

Examples:

- `just key-topup 0 1 2` — +2 ETH top-up on 1st active key
- `just key-topup 0 1 32` — +32 ETH (simulates MaxEB consolidation)

## Full example

```bash
# 1. Assign operator to a group (required for keys to be depositable)
just create-operator-group 0 100

# 2. Add keys
just add-keys 0 2

# 3. Deposit keys (only works after group assignment)
just deposit-keys 2

# 4. Increase effective balance
just key-topup 0 1 2
```

## Other commands

### Key lifecycle

| Command | Description |
|---------|-------------|
| `just remove-key <noId> <keyIndex>` | Remove a specific key |
| `just exit-keys <noId> <count>` | Mark keys as exited |
| `just withdraw-key <noId> <keyIndex> [balance] [penalty]` | Report withdrawal (defaults: 32 ETH, no penalty) |
| `just slash-key <noId> <keyIndex>` | Report slashing |
| `just unvet-keys <noId> <vettedCount>` | Decrease vetted keys count |
| `just exit-request <noId> <validatorIndex> <pubkey>` | Simulate VEBO exit request |

### Target limits

| Command | Description |
|---------|-------------|
| `just target-limit <noId> <limit>` | Set soft validator target limit |
| `just target-limit-forced <noId> <limit>` | Set forced validator target limit |
| `just target-limit-off <noId>` | Remove target limit |

### Penalties

| Command | Description |
|---------|-------------|
| `just report-penalty <noId> <amountEth>` | Report general delayed penalty |
| `just cancel-penalty <noId> <amountEth>` | Cancel general delayed penalty |
| `just settle-penalty <noId>` | Settle general delayed penalty |
| `just compensate-penalty <noId>` | Compensate general delayed penalty |

### MEV stealing

| Command | Description |
|---------|-------------|
| `just report-stealing <noId> <amount>` | Report MEV stealing (amount in wei) |
| `just cancel-stealing <noId> <amount>` | Cancel stealing report |
| `just settle-stealing <noId>` | Settle stealing penalty |
| `just compensate-stealing <noId> <amount>` | Compensate stealing penalty |

### Bond & module management

| Command | Description |
|---------|-------------|
| `just create-bond-debt <noId> <amountEth>` | Create artificial bond debt |
| `just stuck-keys <noId> <count>` | Mark validators as stuck |
| `just warp <days>` | Fast-forward time |

### Module state

| Command | Description |
|---------|-------------|
| `just pause-csm` | Pause module |
| `just resume-csm` | Resume module |
| `just pause-accounting` | Pause accounting |
| `just resume-accounting` | Resume accounting |

### Address management

| Command | Description |
|---------|-------------|
| `just propose-manager <noId> <address>` | Propose new manager address |
| `just confirm-manager <noId>` | Confirm proposed manager |
| `just propose-reward <noId> <address>` | Propose new reward address |
| `just confirm-reward <noId>` | Confirm proposed reward |
