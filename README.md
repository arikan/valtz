## Valtz

**Valtz is a smart contract protocol for creation of validation futures, a novel asset enabling blockchains to secure credible commitments from validators, enhancing security and driving growth from the testnet phase onwards.**

Valtz protocol runs on Ethereum Virtual Machine (EVM) and offers a two-sided marketplace:

- **Blockchain teams** create a futures pool to reward validation commitments, thereby strengthening their chain’s validator base and security in line with their growth.

- **Validators** commit future validation to blockchains by depositing validation tokens and submitting their current proof of validation. This process mints future validation tokens to receive rewards. Upon completing their validation and depositing their future validation tokens, validators claim boost rewards, which are on top of normal staking rewards, incentivizing their participation.

Similar to traditional commodity futures, Valtz validation futures are tradeable, enhancing security and growth of subnets while assessing the price of validation. Validators who join the pool early and later change their positions can sell their futures tokens to other validators who want to earn extra rewards from validation.

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

The Avalanche P-Chain manages staking and delegating across all chains in the Avalanche ecosystem. The P-Chain API can be called from any Avalanche node and provides various endpoints. They can be used for performing off-chain computations before making C-Chain contract calls. Two endpoints are particularly useful for validation:

### **`platform.getBlockchains`**

Returns the list of all blockchains that exist (excluding the P-Chain). https://docs.avax.network/api-reference/p-chain/api#platformgetblockchains

   - Use it for displaying all chains and subnets.

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

### **`platform.getcurrentvalidators`**

Returns the list of all current validators of the Primary Network or a specified subnet. https://docs.avax.network/api-reference/p-chain/api#platformgetcurrentvalidators

This endpoint can be used in the following ways:

1. When a blockchain team provides a `subnetId`, check its details and current validators.

2. Provide a user (C-chain address) a unique message to sign, then verify it using the signature + the message + the P-chain address. If verified, we know this user owns this P-chain address, then check if this address is a validationRewardOwner.
   - `validators[i].signer.publicKey` is the node's BLS public key.
   - `validators[i].validationRewardOwner.addresses` is the potential reward owner adress on P-chain.

3. When a validator provides proof of validation, verify:
    - `endTime` - `startTime` must be equal or greater than the comitted duration
    - `uptime` must be over 80%

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

## TODO

- [ ] Verification mechanism for blockchain teams to join the allowlist for calling createPool
- [ ] Verification mechanism for validation proof while claiming rewards
