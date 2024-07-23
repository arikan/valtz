## Valtz

**Valtz is a smart contract protocol for creation of validation futures, a novel asset enabling blockchains to secure credible commitments from validators, enhancing security and driving growth from the testnet phase onwards.**

Valtz protocol runs on Ethereum Virtual Machine (EVM) and offers a two-sided marketplace:

- **Blockchain teams** create a futures pool to reward validation commitments, thereby strengthening their chain’s validator base and security in line with their growth.

- **Validators** commit future validation to blockchains by depositing validation tokens and submitting their current proof of validation. This process mints future validation tokens to receive rewards. Upon completing their validation and depositing their future validation tokens, validators claim boost rewards, which are on top of normal staking rewards, incentivizing their participation.

Similar to traditional commodity futures, Valtz validation futures are tradeable, enhancing security and growth of subnets while assessing the price of validation.

## Mechanism

The contract in `src/Valtz.sol` consists of the following functionality:

- **createPool**: Creates a futures staking pool for a specific blockchain/subnet. Only allowed creators for a specific subnet can create pools.
    - `_token` The ERC20 token used for staking and rewards
    - `_rewardAmount` The initial amount of tokens for rewards
    - `_boostRate` The boost rate for rewards (1-100)
    - `_requiredDuration` The required staking duration (e.g., 360 days)
    - `_subnetID` The ID of the subnet for this pool

- **depositToPool**: Allows users to deposit tokens into a specific pool. Mints receipt tokens to represent the user's stake and the reward.
    - `_poolId` The ID of the pool to deposit into
    - `_amount` The amount of tokens to deposit

- **claimReward**: Allows users to claim rewards and withdraw their stake.
    - `_poolId` The ID of the pool to claim from
    - `_amount` The amount of receipt/futures token (burned after transferring deposit + rewards)
    - `_validationProof` Proof of required staking duration

- **withdrawReward**: Allows pool creators to withdraw excess rewards. Only the pool creator can withdraw, and only excess rewards can be withdrawn.
    - `_poolId` The ID of the pool to withdraw from
    - `_amount` The amount of rewards to withdraw

- **increasePoolReward**: Allows pool creators to increase the reward balance of a pool. Only the pool creator can increase rewards.
    - `_poolId` The ID of the pool to increase rewards for
    - `_additionalReward` The amount of additional rewards to add

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
Avalanche P-Chain API `platform.getcurrentvalidators` returns the list of all current validators for the Primary Network or for a specified subnet. https://docs.avax.network/reference/avalanchego/p-chain/api#platformgetcurrentvalidators

Using this data:

- When a validator provides a `nodeId`, we can verify if a message is signed by a corresponding private key:
   - Using `signer.publicKey` on P-Chain.
   - Using `validationRewardOwner.addresses` on C-Chain.

- When a blockchain team provides a `subnetId`, we check its details and current validators.

- For validation check, we can use `startTime`, `endTime`, `stakeAmount`, and `uptime`.

```js
platform.getCurrentValidators({
    subnetID: string, // optional
    nodeIDs: string[], // optional
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

## TODO

- [ ] Implement a verification mechanism for blockchain teams to join the allowlist
- [ ] Implement a verification for validation proof while claiming rewards


