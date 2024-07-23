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
    - `_amount` The amount of stake to withdraw
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
