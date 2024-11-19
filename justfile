# Default command runs tests
default: test

# Build the project
build:
    forge build

# Run all tests
test:
    forge test

# Run all tests
watch:
    forge test -vv -w

# Start local Anvil node
anvil:
    anvil --chain-id 1337

# Generate contract ABI in viem TypeScript format
# Usage: just generate-abi <contract_name>
generate-abi contract:
    echo "export default $(forge inspect {{contract}} abi) as const;"

# Deploy contracts locally with signer
# Usage: just deploy-local <valtz_signer_address>
deploy-valtz-local valtz_signer_addr="0xa0Ee7A142d267C1f36714E4a8F75612F20a79720": build
    forge script script/Valtz.s.sol --sig "runWithSigner(address)" {{valtz_signer_addr}} --rpc-url localhost --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploy test token locally with optional recipient
# Usage: just deploy-token-local [recipient_address]
deploy-token-local recipient="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": build
    RECIPIENT={{recipient}} forge script script/OpenToken.s.sol --sig "dev()" --rpc-url localhost --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Full local deployment sequence with signer
# Usage: just local-full-deploy [valtz_signer_address] [recipient_address]
deploy-local valtz_signer_addr="0xa0Ee7A142d267C1f36714E4a8F75612F20a79720" recipient="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266":
    @just deploy-valtz-local {{valtz_signer_addr}}
    @just deploy-token-local {{recipient}}

# Deploy to Fuji testnet with signer
# Usage: PRIVATE_KEY=<your_key> just deploy-fuji-with-signer <valtz_signer_address>
deploy-valtz-fuji valtz_signer_addr:
    forge script script/Valtz.s.sol --sig "runWithSigner(address)" {{valtz_signer_addr}} --rpc-url fuji --broadcast --verify --private-key $PRIVATE_KEY

# Deploy test token to Fuji
# Usage: PRIVATE_KEY=<your_key> just deploy-token-fuji [token_name] [token_symbol]
deploy-token-fuji token_name="ValtzTest" token_symbol="VLTZ-T":
    TOKEN_NAME={{token_name}} TOKEN_SYMBOL={{token_symbol}} forge script script/OpenToken.s.sol --rpc-url fuji --broadcast --verify --private-key $PRIVATE_KEY

