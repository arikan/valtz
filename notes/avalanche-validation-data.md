# Avalanche validation data

The Avalanche P-Chain manages staking and delegating across all chains in the Avalanche ecosystem. The P-Chain API can be called from any Avalanche node and provides various endpoints. They can be used for performing off-chain computations before making C-Chain contract calls. Two endpoints are particularly useful for validation:

## `platform.getBlockchains`

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

## `platform.getcurrentvalidators`

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

## `platform.getTx`

https://docs.avax.network/api-reference/p-chain/api#platformgettx

Returns UTXO transaction details by its ID.

## Blockchain validators and total stake

For a given `subnetID`, number of current validators and total at stake can be listed using `platform.getcurrentvalidators`.

## Verify validator ownership

1. Provide a user (C-chain address) a unique message and ask to sign it with their P-chain address that is a rewardOwner of a validator.
2. User signs it (in their Core wallet or via cli in their node) and provides the signature and their P-chain address.
3. Verify using the signature, P-chain address, and the unique message. If it verifies, then we know this user (C-chain address) owns this P-chain address.
4. Then, check if this P-chain address is a validation reward owner using the P-chain API `validators[i].validationRewardOwner.addresses` endpoint.

## Verify completed validation

1. For this p-chain address, retrieve its previous p-chain transactions
2. Filter the validation transactions and get their details from `validators[i].txID` to check if they are completed validations (still need to check how)
3. Each validations has `start` and `end`, which must be equal or greater than the comitted validation slot

# TODO

- [ ] Verification mechanism for blockchain teams to join the allowlist for calling createPool
