<p align="center">
  <img src="logo.png" width="240" alt="CSM Logo"/>
</p>
<h1 align="center"> Lido Community Staking Module </h1>

## Intro

Lido Community Staking Module (CSM) is a permissionless module allowing community stakers to operate Ethereum validators with lower entry costs. Stakers provide stETH bonds, serving as security collateral, and receive rewards in the form of bond rebase and staking rewards (including execution layer rewards), which are socialized across Lido’s staking modules.

More on CSM in the [docs](https://docs.lido.fi/staking-modules/csm/intro).

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md).

## Getting Started

- Install [Foundry tools](https://book.getfoundry.sh/getting-started/installation) (version 1.2.3, see `.foundryref`)

- Install [Just](https://github.com/casey/just) (version 1.24.0 or later)

- Install [jq](https://jqlang.org/download/) (version 1.6 or later)

> Some Linux distributions (like Arch Linux) might require additional install of [netcat (nc)](https://en.wikipedia.org/wiki/Netcat). The preferred version is OpenBSD.

- Install project dependencies

```bash
just deps
```

- Config environment variables

```bash
cp .env.sample .env
```

Fill vars in the `.env` file with your own values

- Build and test contracts

```bash
just
```

## Run tests

Run unit tests only

```bash
just test-unit
```

For the following tests, make sure that the following variables are set in the `.env` file:

```bash
export CHAIN=hoodi
export RPC_URL=<PUT_YOUR_URL_HERE>
```

Deploy CSM to the fork and run `deployment` and `integration` tests over it

```bash
just test-local
```

Run all tests in one (`unit`, `deployment`, `integration`)

```bash
just test-all
```

## Make a gas report

It requires all unit tests to be green

```bash
just gas-report
```

## Add new dependencies

Dependencies are managed using yarn. To install new dependencies, run:

```bash
yarn add <package-name>
```

Whenever you install new libraries using yarn, make sure to update your
`remappings.txt`.

## Advanced testing scenarios using local fork

Deploy contracts to the local fork

```bash
just deploy-local
```

Set up environment for the local fork
Further test commands require the following environment variables to be set:

```bash
export RPC_URL=http://127.0.0.1:8545
export DEPLOY_CONFIG=./artifacts/local/deploy-hoodi.json
# Optional: utility deployment config for `test-utils`
export UTILS_DEPLOY_CONFIG=./artifacts/local/utils/TwoPhaseFrameConfigUpdate/deploy-hoodi.json
```

The result of deployment is `./artifacts/local/deploy-hoodi.json` deployment config, which is required for integration testing

Verify deploy by running `deployment` tests.
Note that these are meant to be run only right after deployment, so they don't supposed to be green after any actions in the contracts

```bash
just test-deployment
```

Integration tests should pass either before a vote, or after at any state of contracts

```bash
just test-integration
```

There also fork helper scripts to prepare a fork state for e.g. UI testing purposes,
see [fork.just](./fork.just) to get all available commands

```bash
just vote-upgrade
```

After a vote, you can test the contracts in the new state. It includes both `integration` and `vote-upgrade` tests

```bash
just test-post-upgrade
```

Kill fork after testing

```bash
just kill-fork
```

## Deploy on a chain

The following commands are related to the deployment process:

- Dry run of deploy script to be sure it works as expected

```bash
just deploy-live-dry
```

- Broadcast transactions

> Note: pass `--legacy` arg in case of the following error: `Failed to get EIP-1559 fees`

```bash
just deploy-live
```

After that there should be artifacts in the `./artifacts/latest` directory,
which is might be moved to the particular directory and committed

```bash
mv ./artifacts/latest ./artifacts/$CHAIN
```
