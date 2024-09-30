## Valtz

**Valtz is a smart contract protocol for creation of validation futures, a novel asset enabling blockchains to secure credible commitments from validators, enhancing security and driving growth from the testnet phase onwards.**

Valtz protocol runs on Ethereum Virtual Machine (EVM) and offers a two-sided marketplace:

- **Blockchain teams** create a futures pool to reward validation commitments, thereby strengthening their chain’s validator base and security in line with their growth.

- **Validators** commit future validation to blockchains by depositing validation tokens and submitting their current proof of validation. This process mints future validation tokens to receive rewards. Upon completing their validation and depositing their future validation tokens, validators claim boost rewards, which are on top of normal staking rewards, incentivizing their participation.

Similar to traditional commodity futures, Valtz validation futures are tradeable, enhancing security and growth of subnets while assessing the price of validation. Validators who join the pool early and later change their positions can sell their futures tokens to other validators who want to earn extra rewards from validation.

## Mechanism

The Valtz protocol consists of two main contracts:

1. `Valtz.sol`: The factory contract for creating pools
2. `ValtzPool.sol`: The individual pool contract

## Valtz.sol

The `Valtz` contract is responsible for creating new pools and includes the following main functions:

- **createPool**: Creates a new pool with the given configuration. This function is currently permissionless but will be removed in production.

  - `config`: A struct containing the pool configuration parameters

- **adminCreatePool**: Creates a new pool, restricted to accounts with the `POOL_CREATOR_ADMIN_ROLE`.

  - `config`: A struct containing the pool configuration parameters

- **subnetOwnerCreatePool**: Creates a new pool, intended to be restricted to subnet owners (implementation pending).
  - `config`: A struct containing the pool configuration parameters

## ValtzPool.sol

The `ValtzPool` contract represents an individual staking pool and includes the following main functions:

- **initialize**: Initializes the pool with the given configuration (called by the factory contract).

  - `config`: A struct containing the pool configuration parameters

- **deposit**: Allows users to deposit tokens into the pool.

  - `tokens`: The amount of tokens to deposit
  - `receiver`: The address to receive the minted receipt tokens

- **redeem**: Allows users to redeem their staked tokens and claim rewards.

  - `amount`: The amount of receipt tokens to redeem
  - `receiver`: The address to receive the withdrawn tokens and rewards
  - `attestedValidation`: A struct containing validation data
  - `signedAuth`: A struct containing authorization data

- **start**: Starts the pool, allowing deposits and redemptions (only callable by the owner).

- **startAt**: Starts the pool at a specific timestamp (only callable by the owner).

  - `_startTime`: The timestamp to start the pool

- **rescue functions**: Allow the owner to rescue various token types (ERC20, ERC721, ERC1155) and native currency from the contract.

Key features of the ValtzPool contract:

- Uses OpenZeppelin's upgradeable contracts
- Implements ERC20 functionality for receipt tokens
- Includes a boost rate mechanism for rewards
- Tracks validator intervals to prevent double-redemption
- Implements role-based access control for certain functions
- Uses attestations for validation proofs
- Utilizes delegated authorization for redemptions

The contract also includes various view functions for calculating rewards, checking pool status, and retrieving validator intervals.

## Usage

### Build

```sh
forge build
```

### Test

```sh
forge test
```

## Avalanche validation data

The Avalanche P-Chain manages staking and delegating across all chains in the Avalanche ecosystem. The P-Chain API can be called from any Avalanche node and provides various endpoints. They can be used for performing off-chain computations before making C-Chain contract calls. Two endpoints are particularly useful for validation:

### `platform.getBlockchains`

https://docs.avax.network/api-reference/p-chain/api#platformgetblockchains

Returns the list of all blockchains that exist (excluding the P-Chain). Can be used for displaying all chains and subnets.

```js
platform.getBlockchains() ->
{
    blockchains: []{
        id: string,
        name:string,
        subnetID: string,
        vmID: string
    }
}
```

### `platform.getcurrentvalidators`

https://docs.avax.network/api-reference/p-chain/api#platformgetcurrentvalidators

Returns the list of all current validators of the Primary Network or a specified subnet.

```js
platform.getCurrentValidators({
    subnetID: string, // Optional. If omitted, returns the current validators of the Primary Network
    nodeIDs: string[], // Optional. If omitted, returns all current validators. If a specified nodeID is not in the set of current validators, it is not inclunded in the response.
}) -> {
    validators: []{
        txID: string,
        startTime: string,
        endTime: string,
        stakeAmount: string,
        nodeID: string,
        weight: string,
        validationRewardOwner: {
            locktime: string,
            threshold: string,
            addresses: string[]
        },
        delegationRewardOwner: {
            locktime: string,
            threshold: string,
            addresses: string[]
        },
        potentialReward: string,
        delegationFee: string,
        uptime: string,
        connected: bool,
        signer: {
            publicKey: string,
            proofOfPosession: string
        },
        delegatorCount: string,
        delegatorWeight: string,
        delegators: []{
            txID: string,
            startTime: string,
            endTime: string,
            stakeAmount: string,
            nodeID: string,
            rewardOwner: {
                locktime: string,
                threshold: string,
                addresses: string[]
            },
            potentialReward: string,
        }
    }
}
```

### `platform.getTx`

https://docs.avax.network/api-reference/p-chain/api#platformgettx

Returns UTXO transaction details by its ID.

### Blockchain validators and total stake

For a given `subnetID`, number of current validators and total at stake can be listed using `platform.getcurrentvalidators`.

### Verify validator ownership

1. Provide a user (C-chain address) a unique message and ask to sign it with their P-chain address that is a rewardOwner of a validator.
2. User signs it (in their Core wallet or via cli in their node) and provides the signature and their P-chain address.
3. Verify using the signature, P-chain address, and the unique message. If it verifies, then we know this user (C-chain address) owns this P-chain address.
4. Then, check if this P-chain address is a validation reward owner using the P-chain API `validators[i].validationRewardOwner.addresses` endpoint.

### Verify completed validation

1. For this p-chain address, retrieve its previous p-chain transactions
2. Filter the validation transactions and get their details from `validators[i].txID` to check if they are completed validations (still need to check how)
3. Each validations has `start` and `end`, which must be equal or greater than the comitted validation slot

## TODO

- [ ] Verification mechanism for blockchain teams to join the allowlist for calling createPool
