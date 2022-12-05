#!/usr/bin/env bash
set -e

source .env

# Deploy the AlETHRouter using the first anvil account.
forge script script/ToolboxLocal.s.sol:ToolboxLocal \
    -f "http://localhost:8545" \
    --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" \
    -s "deployRouter()" \
    --broadcast \
    -vvvvv

# Write the new router address to the external file.
external=$(jq -c ".chainId[\"1\"]" ./deployments/external.json)
address=$(jq -rc \
    ".transactions[0].contractAddress" \
    ./broadcast/ToolboxLocal.s.sol/1/deployRouter-latest.json)
echo "$external {\"05-router\": \"$address\"}" | jq -s add | jq "{\"chainId\": {\"1\": .}}" > ./deployments/external.json

# Impersonate the Alchemist owner.
cast rpc anvil_impersonateAccount 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 > /dev/null

# Whitelist the deployed router contract.
cast send 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653 \
    --from 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 \
    "add(address)" "$address"

# Stop impersonating the Alchemist owner.
cast rpc anvil_stopImpersonatingAccount 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9 > /dev/null
