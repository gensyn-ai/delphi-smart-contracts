# Gensyn Smart Contracts [![Foundry][foundry-badge]][foundry]
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Installation

This project was built using [Foundry](https://book.getfoundry.sh/). Refer to the Foundry installation instructions [here](https://github.com/foundry-rs/foundry#installation). Installing Foundry is required before working with this project.

After installing Foundry, run the following commands to install the project locally:

```sh
curl -L https://foundry.paradigm.xyz | bash && foundryup
git clone https://github.com/gensyn-ai/delphi-smart-contracts/
cd delphi-smart-contracts
forge install
```

## Running Scripts

### 1. Setup up your env file
Create a `.env` file, following the template outlined in the [`.env.example`](.env.example) file.

### 2. Available Networks
The available networks for the `NETWORK` flag are:
- `anvil`
- `gensyn-testnet`
- `gensyn-mainnet`

Note: Before running scripts on `anvil`, you must first spin up an anvil node.

To spin up an anvil node, simply run the following command:
```bash
anvil
```

### 3a) Deploy Delphi

To deploy Delphi start by filling out the [`DeployDelphi.json`](script/input/deployment/DeployDelphi.json) file.

Note that:
- If you want to use an already deployed token, put its address in `token.address`, and specify its decimals in `token.config.decimals`
- If you want to deploy and use a new token, leave the `token.address` field as `0x0000000000000000000000000000000000000000`, and fill out the `token.config` as desired

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

### 3c) Deploy Gensyn Faucet

To deploy a Gensyn Faucet, start by filling out the [`DeployFaucet.json`](script/input/deployment/DeployFaucet.json) file:

| Field | Description |
|---|---|
| `token` | Address of the deployed Gensyn ERC-20 token. |
| `admin` | Address that will be granted `DEFAULT_ADMIN_ROLE` (can authorize upgrades). |
| `dripManager` | Address that will be granted `DRIP_MANAGER_ROLE` (can update drip time and amount). |
| `dripTime` | Minimum time (in seconds) a user must wait between drip requests. |
| `dripAmount` | Amount of tokens (in wei) dispensed per drip request. |
| `implementation` | Set to `0x0000000000000000000000000000000000000000` to deploy a new implementation, or provide an existing implementation address to reuse it. When reusing, the implementation's `GENSYN_TOKEN` must match `token`. |

Then, to simulate, run:
```bash
make deploy-faucet NETWORK=${your-chosen-network}
```

Or to deploy (without verifying), run:
```bash
make deploy-faucet NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=0
```

Or to deploy and verify, run:
```bash
make deploy-faucet NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=1
```

## 4. Gnosis Safe Operations

This section describes how to perform operations on a Gnosis Safe, such as removing an owner or executing a custom transaction.

### 4.1 Deploying a new Safe Proxy

To deploy a Safe, start by filling out the [`DeploySafe.json`](script/input/deployment/DeploySafe.json) file:

Then, to simulate, run:
```bash
make deploy-safe NETWORK=${your-chosen-network}
```

Or to deploy (without verifying), run:
```bash
make deploy-safe NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=0
```

Or to deploy and verify, run:
```bash
make deploy-safe NETWORK=${your-chosen-network} BROADCAST=1 VERIFY=1
```

### 4.2 The Signing Process

All Gnosis Safe transactions require one or more signatures from the safe owners. The number of required signatures is determined by the safe's threshold. The general process for signing a transaction is as follows:

1.  **Launch the Safe Signing UI:**
    ```bash
    make run-safe-signing-ui
    ```
2.  **Navigate to the UI:** Open `http://localhost:8000/safe-signing-ui.html` in your browser.
3.  **Connect and Fill:** Connect your wallet and fill out the form fields for the transaction you want to sign. You will need the safe's nonce, which can be obtained by running:
    ```bash
    cast call ${safeProxyAddress} "nonce()(uint256)" --rpc-url ${network}
    ```
4.  **Sign:** Click the `Sign EIP-712` button and sign the transaction in your wallet. The signature will be displayed in the `Signature` box.
5.  **Collect Signatures:** Copy the signature and save it. Repeat this process for each required owner until the threshold is met.

### 4.3 Removing an Owner

To remove an owner from the safe:

1.  **Prepare the Transaction:** Fill out the `script/input/actions/SafeRemoveOwner.json` file with the address of the owner to be removed and the new threshold for the safe.
2.  **Generate Calldata:** Run the following command to generate the transaction calldata:
    ```bash
    make get-safe-remove-owner-calldata NETWORK=${your-chosen-network}
    ```
3.  **Collect Signatures:** Follow the process described in section 4.1 to collect signatures for this transaction. Add the collected signatures to the `signatures` array in `SafeRemoveOwner.json`.
4.  **Execute the Transaction:** Once you have enough signatures, execute the transaction by running:
    ```bash
    make safe-remove-owner NETWORK=${your-chosen-network} BROADCAST=1
    ```

### 4.4 Performing a Custom Transaction

To execute a custom transaction through the safe:

1.  **Generate Calldata:** First, generate the calldata for the action you want to perform. For example, to transfer 123 ERC20 tokens to a specific address, you would run:
    ```bash
    cast calldata "transfer(address,uint)" 0x71C7656EC7ab88b098defB751B7401B5f6d8976F 123e18
    ```
2.  **Prepare the Transaction:** Fill out the `script/input/actions/SafeTransaction.json` file with the details of your transaction, including the calldata generated in the previous step.
3.  **Collect Signatures:** Follow the process described in section 4.1 to collect the required signatures. Add them to the `signatures` array in `SafeTransaction.json`.
4.  **Execute the Transaction:** Execute the transaction by running:
    ```bash
    make safe-exec-transaction NETWORK=${your-chosen-network} BROADCAST=1
    ```
