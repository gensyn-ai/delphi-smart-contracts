# Gensyn Smart Contracts [![Foundry][foundry-badge]][foundry]
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Installation

This project was built using [Foundry](https://book.getfoundry.sh/). Refer to the Foundry installation instructions [here](https://github.com/foundry-rs/foundry#installation). Installing Foundry is required before working with this project.

After installing Foundry, run the following commands to install the project locally:

```sh
git clone https://github.com/gensyn-ai/delphi-smart-contracts/
cd delphi-smart-contracts
git submodule update --init --recursive
```

Note: All the following scripts should be run from the repository root

## Running Scripts

### 1. Setup up your env file
Create a `.env` file, following the template outlined in the [`.env.example`](.env.example) file.

### 2. Available Networks
The available networks for the `NETWORK` flag are:
- `anvil`
- `gensyn-testnet`
- `gensyn-mainnet`

> **Mainnet guard:** `BaseScript`'s `broadcast` modifier currently reverts on the Gensyn mainnet chain id (685689), so every scripted run — including simulation — refuses to run against `gensyn-mainnet`. Remove or gate that check deliberately when a mainnet deploy is actually intended.

> **Interactive signer:** all on-chain `make` targets pass `--interactives 1` to `forge script`, so they require a real terminal (TTY) where you type the private key when prompted. They will fail with `vm.startBroadcast: Device not configured` if run non-interactively (e.g. piped or in CI).

Note: Before running scripts on `anvil`, you must first spin up an anvil node.

To spin up an anvil node, simply run the following command:
```bash
anvil
```

### 3a) Deploy Delphi

To deploy Delphi start by filling out the [`DeployDelphi.json`](script/input/deployment/DeployDelphi.json) file.

Note that:
- If you want to use an already deployed token, put its address in `token.address` (the `token.config` section will be ignored)
- If you want to deploy and use a new mock token (6 decimals), leave the `token.address` field as `0x0000000000000000000000000000000000000000`, and fill out the `token.config` as desired

Then, to simulate, run:
```bash
make deploy-delphi NETWORK=${your-chosen-network}
```

Or to deploy (without verifying), run:
```bash
make deploy-delphi NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=0
```

Or to deploy and verify, run:
```bash
make deploy-delphi NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=1
```

For example, to deploy and verify on `Gensyn Testnet`, you would run:
```bash
make deploy-delphi NETWORK=gensyn-testnet BROADCAST=1 VERIFY=1
```

### 3b) Create a Delphi Market
To create a Delphi market, start by filling out the [`CreateMarket.json`](script/input/actions/CreateMarket.json) file.

To view the network's `block.timestamp`, run the following command:
```bash
make get-block-timestamp NETWORK=${your-chosen-network}
```

Then, to simulate, run:
```bash
make create-market NETWORK=${your-chosen-network}
```

Then, to execute
```bash
make create-market NETWORK=${your-chosen-network} BROADCAST=1
```

### 3c) Deploy Truebit Oracle Relayer

To deploy a Truebit Oracle Relayer, start by filling out the [`DeployTruebitOracleRelayer.json`](script/input/deployment/DeployTruebitOracleRelayer.json) file:

| Field | Description |
|---|---|
| `watchTower` | Address of the Truebit WatchTower the relayer submits execution requests to. |
| `owner` | Address that will own the relayer (can authorize UUPS upgrades). |
| `gateway` | Address of the deployed `LmsrGateway`. |
| `oracleFeeRecipient` | Address that receives the oracle fee on successful market settlement. |
| `executionTimeout` | Truebit task execution timeout (in seconds). Must be non-zero. |
| `async` | Whether the Truebit task executes asynchronously. |
| `implementation` | Set to `0x0000000000000000000000000000000000000000` to deploy a new implementation, or provide an existing implementation address to reuse it. |

Then, to simulate, run:
```bash
make deploy-truebit-oracle-relayer NETWORK=${your-chosen-network}
```

Or to deploy (without verifying), run:
```bash
make deploy-truebit-oracle-relayer NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=0
```

Or to deploy and verify, run:
```bash
make deploy-truebit-oracle-relayer NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=1
```

Note: After deployment, the gateway owner must wire the relayer into the gateway via `setOracleRelayer(relayerProxy)`. Markets cannot be created until the gateway has an oracle relayer set.

### 3d) Deploy Timelock

To deploy an OpenZeppelin `TimelockController` (open executor, no admin), start by filling out the [`DeployTimelock.json`](script/input/deployment/DeployTimelock.json) file:

| Field | Description |
|---|---|
| `proposer` | Address granted the proposer (and canceller) role on the timelock. |
| `timelock.minDelay` | Minimum delay (in seconds) between scheduling and executing an operation. |

Then, to simulate, run:
```bash
make deploy-timelock NETWORK=${your-chosen-network}
```

Or to deploy (without verifying), run:
```bash
make deploy-timelock NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=0
```

Or to deploy and verify, run:
```bash
make deploy-timelock NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=1
```

## Testing

To run the full test suite:
```bash
forge test
```

To generate a coverage report (requires `lcov`/`genhtml`, e.g. `brew install lcov`):
```bash
make run-tests-with-coverage
```

This runs the unit/fuzz suites and the invariant suite as separate shards (the invariant suite is serialized to avoid running out of memory under coverage instrumentation), merges the tracefiles into `lcov.info`, and generates an HTML report in `coverage/`. The fork test suite is excluded — it needs a live RPC and `ALCHEMY_API_KEY`.
